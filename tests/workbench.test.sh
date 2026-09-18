#!/usr/bin/env bash
# Static checks for the workbench sandbox (docker/workbench/, home/.local/bin/workbench).
#
# Coverage (no docker/colima needed - these are repo-shape checks):
# - shell syntax: the wrapper (bash), workbench-init, and the pre-push tripwire (sh);
# - the authored pi configs parse as JSON and declare the expected $COHERE_API_KEY
#   env references (secret-free by construction);
# - the baked opencode.jsonc parses as a JS object literal (JSONC subset) and
#   carries the sandbox permission block;
# - the Dockerfile pins stay sha256-gated and its hygiene ENV list stays in sync
#   with workbench-init's .zshenv block;
# - the wrapper's mount set is exactly the spec's four host paths (+ named
#   volumes), and the never-mount list is absent from it;
# - the git template hook is executable and refuses main/master rewrites.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BENCH="$ROOT/docker/workbench"
WRAPPER="$ROOT/home/.local/bin/workbench"

# --- shell syntax --------------------------------------------------------------
bash -n "$WRAPPER" \
  && pass "wrapper parses (bash -n)" \
  || fail "wrapper syntax"

for script in "$BENCH/workbench-init" "$BENCH/git-template/hooks/pre-push"; do
  sh -n "$script" \
    && pass "$(basename "$script") parses (sh -n)" \
    || fail "$(basename "$script") syntax"
done

# --- authored pi configs: valid JSON, secret-free -------------------------------
for f in "$ROOT/home/.pi/agent/settings.json" "$ROOT/home/.pi/agent/models.json"; do
  jq -e . "$f" >/dev/null \
    && pass "$(basename "$f") parses as JSON" \
    || fail "$(basename "$f") JSON"
done
if grep -E '"apiKey": *"' "$ROOT/home/.pi/agent/models.json" | grep -v '\$COHERE_API_KEY' | grep -v '"dummy"' | grep -q .; then
  fail "pi models.json carries a non-env apiKey"
else
  pass "pi models.json apiKey values are env references only"
fi

# --- baked opencode config: parses, carries the sandbox permission block --------
oc_parse="$(node -e "
  const src = require('fs').readFileSync('$BENCH/config/opencode/opencode.jsonc', 'utf8');
  // JSONC subset used here is a JS object literal; evaluates without executing code.
  const o = (new Function('return (' + src + ')'))();
  console.log(JSON.stringify({permission: o.permission, providers: Object.keys(o.provider || {}), autoupdate: o.autoupdate}));
" 2>/dev/null)"
[ -n "$oc_parse" ] \
  && pass "opencode.jsonc parses (JSONC literal)" \
  || fail "opencode.jsonc parse"

for needle in '"git push --force*":"deny"' '"doom_loop":"ask"' '"external_directory":"ask"' '"websearch":"deny"' '"autoupdate":false' '"oss-model-vault-v2"' '"cohere-oss"'; do
  case "$oc_parse" in
    *"$needle"*) pass "opencode.jsonc carries $needle" ;;
    *) fail "opencode.jsonc missing $needle" ;;
  esac
done
case "$oc_parse" in
  *'"*.env":"deny"'*) pass "opencode.jsonc carries the .env read-deny (restated default)" ;;
  *) fail "opencode.jsonc missing the .env read-deny" ;;
esac

# --- Dockerfile pins stay sha256-gated ------------------------------------------
for pin in "herdr.*v0.8.0" "treehouse-v2.1.1" "no-mistakes-v1.72.0" "mise-v2026.9.10" "pi-coding-agent@0.85.1" "opencode-ai@1.18.31" "tasks-axi@0.2.5" "gh-axi@0.1.30" "chrome-devtools-axi@0.1.29" "quota-axi@0.1.43" "lavish-axi@0.1.50" "node:24-bookworm-slim" "fd-find" "extended-keys"; do
  grep -q "$pin" "$BENCH/Dockerfile" \
    && pass "Dockerfile pins $pin" \
    || fail "Dockerfile missing pin $pin"
done
sha_count="$(grep -c 'SHA256=\|_SHA=' "$BENCH/Dockerfile")"
[ "$sha_count" -ge 8 ] \
  && pass "Dockerfile sha256 gates present ($sha_count assignments)" \
  || fail "Dockerfile sha256 gates too few ($sha_count)"

# --- hygiene env: Dockerfile ENV and init .zshenv stay in sync -------------------
for var in PI_SKIP_VERSION_CHECK PI_OFFLINE PI_TELEMETRY OPENCODE_DISABLE_AUTOUPDATE OPENCODE_DISABLE_LSP_DOWNLOAD GIT_TERMINAL_PROMPT FM_HOME NPM_CONFIG_CACHE; do
  grep -q "$var" "$BENCH/Dockerfile" && grep -q "$var" "$BENCH/workbench-init" \
    && pass "$var in both Dockerfile ENV and init zshenv" \
    || fail "$var drifted between Dockerfile and init"
done
grep -q 'AcceptEnv COHERE_API_KEY GH_TOKEN' "$BENCH/Dockerfile" \
  && pass "sshd AcceptEnv drop-in baked" \
  || fail "sshd AcceptEnv drop-in missing"
if grep -qE 'ENV .*(COHERE_API_KEY|GH_TOKEN)=' "$BENCH/Dockerfile" || grep -qE 'export (COHERE_API_KEY|GH_TOKEN)=' "$BENCH/workbench-init"; then
  fail "a secret var is baked into image env or zshenv"
else
  pass "no secret baked into image ENV or zshenv (per-session injection only)"
fi

# --- wrapper mount topology ------------------------------------------------------
for host_path in '$HOME/work:$HOME/work' \
                 '$HOME/repos/github/cohere-ai:$HOME/repos/github/cohere-ai' \
                 '$HOME/repos/github/reliant-ai:$HOME/repos/github/reliant-ai' \
                 '$HOME/firstmate:$HOME/firstmate' \
                 '$HOME/.firstmate:$HOME/.firstmate' \
                 '$HOME/.treehouse:$HOME/.treehouse'; do
  grep -qF -- "-v \"$host_path\" \\" "$WRAPPER" \
    && pass "wrapper mounts $host_path rw at identical path" \
    || fail "wrapper missing mount $host_path"
done
for volume in workbench-pi-agent workbench-opencode-data workbench-npm-cache workbench-pnpm-cache workbench-mise; do
  grep -q "$volume" "$WRAPPER" \
    && pass "wrapper mounts named volume $volume" \
    || fail "wrapper missing volume $volume"
done
for never in '.secrets' '.ssh"' '.config/gh' 'docker.sock'; do
  allowed=0
  case "$never" in
    '.ssh"') grep -q -- "-v .*\.ssh" "$WRAPPER" && allowed=1 ;;
    *) grep -q -- "-v .*$never" "$WRAPPER" && allowed=1 ;;
  esac
  [ "$allowed" -eq 0 ] \
    && pass "wrapper never mounts $never" \
    || fail "wrapper mounts $never"
done
grep -q '/docker/workbench/config/pi-agent/' "$ROOT/.gitignore" \
  && pass "staged pi config build context is gitignored" \
  || fail "staged pi config build context not gitignored"
if grep -q 'find-generic-password\|env.local' "$WRAPPER"; then
  pass "wrapper reads secrets from the keychain or env.local"
else
  fail "wrapper reads neither keychain nor env.local"
fi
grep -q 'env.local' "$WRAPPER" \
  && pass "wrapper reconciles home/env.local into the keychain at up" \
  || fail "wrapper ignores home/env.local"
grep -q 'themes' "$WRAPPER" \
  && pass "wrapper stages pi themes into the build context" \
  || fail "wrapper does not stage pi themes"
grep -q 'pi-agent/themes' "$BENCH/workbench-init" \
  && pass "init seeds pi themes when absent" \
  || fail "init does not seed pi themes"
grep -q 'skills@latest add mattpocock/skills' "$BENCH/Dockerfile" \
  && pass "image bakes the mattpocock skills pack" \
  || fail "mattpocock skills pack not baked"
grep -q 'agents/skills' "$BENCH/workbench-init" \
  && pass "init backfills pi skill symlinks for existing volumes" \
  || fail "init does not backfill pi skill symlinks"
for root in '/Users/matt/firstmate' '/Users/matt/.firstmate' '/Users/matt/.treehouse'; do
  grep -qF "\"$root\": true" "$BENCH/Dockerfile" \
    && pass "image bakes trust for $root" \
    || fail "trust.json bake missing $root"
done
grep -q 'repos/public/firstmate' "$BENCH/Dockerfile" "$BENCH/workbench-init" "$WRAPPER" \
  && fail "stale pre-split firstmate path (repos/public/firstmate) still referenced" \
  || pass "no stale repos/public/firstmate references"
grep -q 'pi-agent/trust.json' "$BENCH/workbench-init" \
  && pass "init merges baked trust roots without overriding runtime trust" \
  || fail "init does not merge trust.json"
grep -q 'firstmate/projects' "$WRAPPER" \
  && pass "wrapper repo search includes the fleet projects dir" \
  || fail "wrapper repo search missing firstmate/projects"
grep -q '"firstmate"\|firstmate)' "$WRAPPER" \
  && pass "wrapper maps the bare name firstmate to the code root" \
  || fail "wrapper cannot resolve firstmate"
grep -qF 'arg="${1:-$PWD}"' "$WRAPPER" \
  && pass "wrapper defaults the repo to the current directory" \
  || fail "wrapper cannot default the repo to the current directory"
grep -q 'send-keys' "$WRAPPER" \
  && pass "agent runs in a zsh pane (exiting agent lands in repo shell)" \
  || fail "agent still replaces the tmux pane - no shell exit path"
[ -f "$ROOT/home/.pi/agent/themes/rose-pine-moon.json" ] \
  && pass "authored rose-pine-moon theme present to stage" \
  || fail "rose-pine-moon theme source missing"

# --- pre-push tripwire ------------------------------------------------------------
[ -x "$BENCH/git-template/hooks/pre-push" ] \
  && pass "pre-push tripwire is executable" \
  || fail "pre-push tripwire not executable"
grep -q 'refs/heads/main|refs/heads/master' "$BENCH/git-template/hooks/pre-push" \
  && pass "pre-push tripwire guards main/master" \
  || fail "pre-push tripwire ignores main/master"
grep -q 'no-verify' "$BENCH/git-template/hooks/pre-push" \
  && pass "pre-push tripwire labels its own bypass (honest labeling)" \
  || fail "pre-push tripwire does not label its bypass"

# --- tripwire behavior: refuse force-push + delete of main, allow fast-forward ----
tmp_root=$(dotfiles_test_tmproot workbench)
hook="$BENCH/git-template/hooks/pre-push"
frepo="$tmp_root/repo"
dotfiles_git_init_commit "$frepo"
main_sha="$(git -C "$frepo" rev-parse HEAD)"
git -C "$frepo" commit -q --allow-empty -m second
second_sha="$(git -C "$frepo" rev-parse HEAD)"
zero=0000000000000000000000000000000000000000

out="$(printf 'refs/heads/main %s refs/heads/main %s\n' "$second_sha" "$main_sha" | (cd "$frepo" && "$hook" origin .) 2>&1)" \
  && pass "tripwire allows fast-forward push of main" \
  || fail "tripwire blocked a fast-forward push: $out"

out="$(printf 'refs/heads/main %s refs/heads/main %s\n' "$main_sha" "$second_sha" | (cd "$frepo" && "$hook" origin .) 2>&1)"
case "$out" in
  *"non-fast-forward"*) pass "tripwire refuses force-push of main" ;;
  *) fail "tripwire let a force-push of main through" ;;
esac

out="$(printf 'refs/heads/main %s refs/heads/main %s\n' "$zero" "$second_sha" | (cd "$frepo" && "$hook" origin .) 2>&1)"
case "$out" in
  *"refusing to delete"*) pass "tripwire refuses deletion of main" ;;
  *) fail "tripwire let a deletion of main through" ;;
esac

out="$(printf 'refs/heads/feat %s refs/heads/feat %s\n' "$main_sha" "$second_sha" | (cd "$frepo" && "$hook" origin .) 2>&1)" \
  && pass "tripwire leaves non-main branches alone" \
  || fail "tripwire blocked a feature branch: $out"

# --- home.nix links the wrapper ---------------------------------------------------
grep -q '.local/bin/workbench' "$ROOT/home.nix" \
  && pass "home.nix links the workbench wrapper" \
  || fail "home.nix does not link workbench"
if grep -qE '\.local/bin/(agentbox|pi-box)' "$ROOT/home.nix"; then
  fail "home.nix still links a retired wrapper"
else
  pass "retired wrappers (agentbox, pi-box) are unlinked"
fi

# --- pi review mode: tool-surface allowlist per spec's pi row ---------------------
grep -q 'pi-review' "$WRAPPER" \
  && pass "wrapper offers pi-review" \
  || fail "wrapper lacks pi-review"
grep -q -- '--tools read,grep,find,ls' "$WRAPPER" \
  && pass "pi-review pins the read-only tool allowlist" \
  || fail "pi-review allowlist differs from spec"

# --- login-shell landing must not override an explicit pane cwd -------------------
grep -qF '[ "$PWD" = "$HOME" ] && cd "$FM_HOME"' "$BENCH/Dockerfile" \
  && pass "zprofile fleet-home landing only fires from HOME" \
  || fail "zprofile teleports repo panes into FM_HOME"

# --- baked models.dev cache fallback (spec 7: network + baked-cache) ---------------
grep -q 'models.dev/api.json' "$BENCH/Dockerfile" \
  && pass "Dockerfile bakes the models.dev catalog" \
  || fail "models.dev baked cache missing from Dockerfile"
grep -q 'models.json' "$BENCH/workbench-init" \
  && pass "init seeds the baked models.dev cache" \
  || fail "init does not seed the models.dev cache"

dotfiles_test_cleanup
echo "workbench tests: all passed"
