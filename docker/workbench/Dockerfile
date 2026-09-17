# workbench: the disposable sandbox for agentic coding (pi, opencode, and the
# firstmate fleet) on colima's docker VM. Sandbox spec v1: the container and its
# mount topology are the ONLY load-bearing boundary; guardrails baked here live
# on the image layer so tampering resets with the container. Nothing durable
# lives in the rootfs: `docker rm` is safe anytime.
#
# Build via the `workbench` wrapper (home/.local/bin/workbench), never by hand:
# the wrapper stages home/.pi/agent/{settings.json,models.json} (the authored
# source) into config/pi-agent/ before building, so those COPYs resolve.
#
# Seeded from the retired agent-box image (22+ hours of precedent on this
# machine): uid 501 with HOME=/Users/matt for identical-path sharing, sshd as
# PID 1 with env materialized into .zshenv, sha256-pinned binaries.

FROM node:24-bookworm-slim

# gh has no Debian package; GitHub publishes its own apt repo, keyed by its
# archive keyring. git-lfs: host repos carry LFS pointers; without it in-tree
# checkouts/clones referencing LFS content break. fd: pi shells out to `fd` for
# its file pickers - Debian ships the binary as `fdfind`, so symlink it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git git-lfs ripgrep fd-find curl ca-certificates \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && apt-get install -y --no-install-recommends openssh-server tmux zsh jq \
 && rm -rf /var/lib/apt/lists/*

# Binary pins, each sha256-gated like herdr (same policy: official GitHub
# release assets - never a floating package-manager latest - plus a post-install
# version gate). Versions track the host fleet (host is the version leader).
# TARGETARCH is set by buildkit (docker default); arm64 is the colima path.
ARG TARGETARCH
RUN set -eu; \
  case "$TARGETARCH" in \
    arm64) ASSET=herdr-linux-aarch64; SHA256=f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87 ;; \
    amd64) ASSET=herdr-linux-x86_64;  SHA256=b872ea7e40fa2cb17e857ac9b62b1bf26db7b403c622f5d2f3f5b35f6e9acd28 ;; \
    *) echo "unsupported TARGETARCH $TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL --max-filesize 25000000 \
    "https://github.com/ogulcancelik/herdr/releases/download/v0.8.0/$ASSET" \
    -o /tmp/herdr; \
  echo "$SHA256  /tmp/herdr" | sha256sum -c -; \
  install -m 0755 /tmp/herdr /usr/local/bin/herdr; \
  rm /tmp/herdr; \
  version="$(herdr --version | awk '{print $2; exit}')"; \
  [ "$version" = "0.8.0" ]; \
  protocol="$(herdr status --json | jq -r '.client.protocol // empty')"; \
  [ -n "$protocol" ] && [ "$protocol" -ge 16 ]

RUN set -eu; \
  case "$TARGETARCH" in \
    arm64) A=arm64; TH_SHA=980367c0233274eb3181a19a2ca8ec69d09b4a588ba27367937d336f9a2c938e; \
            NM_SHA=92f402654bdea845ded9cebca41fd565e2ae654bb81c9ce2282e0a2610df8736; \
            MISE_SHA=1b46a14314c18f9bbce4bf6f88cc1fb3b31be8dd2b23327a851555f4e144fc61 ;; \
    amd64) A=amd64; TH_SHA=2fe3e01220ae51a967c3e5ba6ccf10ec83bdbae8e420368d194285a8d04c9ef8; \
           NM_SHA=c226b69b8b8115827d2e438ea8b32eaff9b89291a1d2fddc5ef2449017b8d927; \
           MISE_SHA=f917e52216924ef0a8b4eca3f7004dfcff3b94665716ac5685fd53006a491eee ;; \
    *) echo "unsupported TARGETARCH $TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/kunchenguid/treehouse/releases/download/v2.1.1/treehouse-v2.1.1-linux-$A.tar.gz" -o /tmp/treehouse.tgz; \
  echo "$TH_SHA  /tmp/treehouse.tgz" | sha256sum -c -; \
  tar xzf /tmp/treehouse.tgz -C /tmp treehouse; \
  install -m 0755 /tmp/treehouse /usr/local/bin/treehouse; \
  curl -fsSL "https://github.com/kunchenguid/no-mistakes/releases/download/v1.72.0/no-mistakes-v1.72.0-linux-$A.tar.gz" -o /tmp/no-mistakes.tgz; \
  echo "$NM_SHA  /tmp/no-mistakes.tgz" | sha256sum -c -; \
  tar xzf /tmp/no-mistakes.tgz -C /tmp no-mistakes; \
  install -m 0755 /tmp/no-mistakes /usr/local/bin/no-mistakes; \
  case "$TARGETARCH" in \
    arm64) MISE_ASSET=mise-v2026.9.10-linux-arm64 ;; \
    amd64) MISE_ASSET=mise-v2026.9.10-linux-x64 ;; \
  esac; \
  curl -fsSL "https://github.com/jdx/mise/releases/download/v2026.9.10/$MISE_ASSET" -o /tmp/mise; \
  echo "$MISE_SHA  /tmp/mise" | sha256sum -c -; \
  install -m 0755 /tmp/mise /usr/local/bin/mise; \
  rm /tmp/treehouse.tgz /tmp/treehouse /tmp/no-mistakes.tgz /tmp/no-mistakes /tmp/mise; \
  treehouse --version | grep -q "2.1.1"; \
  no-mistakes --version | grep -q "v1.72.0"; \
  mise --version | grep -q "2026.9.10"

# Agent + fleet CLIs, all pinned at build. Pins track the host fleet.
# Deliberate: --ignore-scripts on everything except opencode-ai, whose npm
# install needs its postinstall to fetch the platform binary.
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.85.1 \
      tasks-axi@0.2.5 gh-axi@0.1.30 chrome-devtools-axi@0.1.29 \
      quota-axi@0.1.43 lavish-axi@0.1.50 \
 && npm install -g opencode-ai@1.18.31

# The workbench shares the host fleet layout: agent's HOME is /Users/matt so
# paths spelled identically on the host (~/work, ~/repos, the ~/firstmate
# symlink into the firstmate checkout) resolve unchanged inside. uid 501
# matches the macOS first user, so files on colima's virtiofs share of host
# $HOME stay readable/writable. Password '*' means no password login but the
# account is not locked, so ssh pubkey auth works. /Users/matt itself is
# container-local; only the mounted subtrees and named volumes land on it.
# The ~/firstmate symlink matches the host spelling (FM_HOME resolves through
# it to the mounted checkout at repos/public/firstmate).
RUN install -d /Users \
 && useradd --create-home --home-dir /Users/matt --shell /usr/bin/zsh \
      --uid 501 --password '*' agent \
 && ln -s /Users/matt/repos/public/firstmate /Users/matt/firstmate

# Baked, secret-free configs. pi settings.json/models.json are staged copies of
# home/.pi/agent/ (apiKey values are $COHERE_API_KEY env references, never
# values); opencode.jsonc is authored for the sandbox (host config + the baked
# permission guardrails; providers resolve {env:COHERE_API_KEY}). workbench-init
# seeds these into place only when absent, so runtime changes survive image
# rebuilds. No auth file is baked or mounted anywhere.
COPY config/pi-agent/ /opt/workbench/pi-agent/
COPY config/opencode/opencode.jsonc /opt/workbench/opencode/opencode.jsonc

# models.dev catalog baked at build as the offline/backstop copy opencode falls
# back to when the network fetch fails (spec: network + baked-cache fallback).
RUN curl -fsSL https://models.dev/api.json -o /opt/workbench/opencode/models.json \
 && test "$(stat -c %s /opt/workbench/opencode/models.json)" -gt 10000

# The pre-push tripwire (speed bump, honestly labeled - --no-verify bypasses
# it): refuses non-fast-forward updates to and deletions of main/master.
# Wired in via the system gitconfig's init.templateDir below so every repo
# created or used in the workbench picks it up; the enforceable layer is
# GitHub branch protection, outside the container.
COPY git-template /usr/local/share/workbench/git-template

# System git policy, root-owned: ssh-style and host ssh-alias remotes rewrite
# to HTTPS (no host ssh keys in the sandbox; GH_TOKEN + gh's credential helper
# authenticate pushes). A per-session GH_TOKEN is injected by the wrapper.
RUN printf '%s\n' \
      '[init]' \
      '	templateDir = /usr/local/share/workbench/git-template' \
      '[url "https://github.com/"]' \
      '	insteadOf = git@github.com:' \
      '	insteadOf = ssh://git@github.com/' \
      '	insteadOf = git@github-cohere:' \
      '	insteadOf = git@github-personal:' \
      '	insteadOf = git@github-reliant:' \
      '[credential "https://github.com"]' \
      '	helper = "!/usr/bin/gh auth git-credential"' \
      > /etc/gitconfig

# sshd: the wrapper injects secrets per session over ssh (SetEnv on the client,
# accepted here), keeping the container-wide environment secret-free
# (docker inspect shows nothing; docker rm ends a value's life).
RUN printf '%s\n' \
      '# workbench: per-session secret injection over ssh (see workbench wrapper)' \
      'AcceptEnv COHERE_API_KEY GH_TOKEN' \
      > /etc/ssh/sshd_config.d/workbench.conf

# pi npm/git packages declared in the baked settings.json, pre-installed at
# build (deterministic; keeps first boot offline-tolerant; PI_OFFLINE=1 is set
# only below, after this step). They land in /Users/matt/.pi/agent, which a
# fresh workbench-pi-agent named volume is seeded from at container create -
# so the baked settings/models/themes and package trees ride the docker volume
# seed and need no first-boot network.
USER agent
ENV HOME=/Users/matt
RUN mkdir -p "$HOME/.pi/agent" \
 && cp -R /opt/workbench/pi-agent/. "$HOME/.pi/agent/" \
 && set -e; \
    for pkg in $(jq -r '.packages[]' "$HOME/.pi/agent/settings.json"); do \
      pi install "$pkg" </dev/null; \
    done
# tmux: pi's TUI wants extended-keys (modified Enter etc). Container-wide
# default; users can still override with their own ~/.tmux.conf.
RUN printf '%s\n' 'set -g extended-keys on' > /Users/matt/.tmux.conf
# mise activates per interactive shell; the shims dir joins PATH via the
# init-written .zshenv so pinned per-repo runtimes also resolve non-interactively.
# Idiomatic version files (.nvmrc, .node-version) are off by default in recent mise;
# enable them alongside .tool-versions (the spec's per-repo resolution inputs).
RUN printf '%s\n' \
      'eval "$(mise activate zsh)"' \
      > "$HOME/.zshrc" \
 && printf '%s\n' \
      '# land in the fleet home on interactive ssh login, as on the host' \
      'cd "$FM_HOME" 2>/dev/null || true' \
      > "$HOME/.zprofile" \
 && install -d -m 755 "$HOME/.config/mise" \
 && printf '%s\n' \
      '[settings]' \
      '# mise disables idiomatic version files by default; the sandbox wants them' \
      'idiomatic_version_file_enable_tools = ["node", "python"]' \
      > "$HOME/.config/mise/config.toml"

USER root
COPY workbench-init /usr/local/sbin/workbench-init
RUN chmod 755 /usr/local/sbin/workbench-init

# Hygiene: a pinned image must not self-update or phone home. This list is
# duplicated into .zshenv by workbench-init (sshd scrubs login-shell env);
# keep the two in sync.
ENV PI_SKIP_VERSION_CHECK=1 PI_OFFLINE=1 PI_TELEMETRY=0 \
    OPENCODE_DISABLE_AUTOUPDATE=1 OPENCODE_DISABLE_LSP_DOWNLOAD=1 \
    GIT_TERMINAL_PROMPT=0 \
    FM_HOME=/Users/matt/firstmate NPM_CONFIG_CACHE=/Users/matt/.cache/npm

WORKDIR /Users/matt

# sshd as PID 1, as root (privilege separation); logins drop to uid 501.
ENTRYPOINT ["/usr/local/sbin/workbench-init"]
