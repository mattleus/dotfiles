# pstack (github.com/cursor/plugins/tree/main/pstack, Lauren Tan, MIT): an Agent Skills
# pack plus subagents. The `pstack` flake input pins it to one commit of cursor/plugins,
# so nothing changes until a deliberate bump.
#
# Where it lands:
#   ~/.agents/skills/<name>        North Code, opencode, Cursor, Codex
#   ~/.claude/skills/<name>        Claude Code (North Code and Cursor read it too)
#   ~/.claude/agents/comment-sicko.md   subagent for Claude Code, North Code and Cursor
#   opencode.jsonc `agent.comment-sicko`   the same subagent for opencode, whose prompt is
#                                  ~/.local/share/pstack/opencode/comment-sicko.md
#   ~/.local/share/pstack          the whole pinned pack, so skills' `<pstack>` paths
#                                  (docs/harness/claude-code.md and the like) resolve
#
# Bump the pin: change the rev in flake.nix's `pstack.url`, run `nix flake update pstack`,
# then `rebuild`. The asserts below fail the build if an excluded or renamed skill
# disappeared upstream. A new upstream skill whose name a personal skill already has fails
# activation at pstackCheckClashes, before anything is linked; exclude or rename it here.
#
# Change what's installed: edit `excluded` or `renamed` below, then `rebuild`.
# home-manager removes links that are no longer declared. A new pstack skill reaches a
# North Code thread from its next message, and the $ menu after North Code restarts.
{ config, pkgs, lib, pstack, ... }:

let
  # Not linked anywhere.
  #   tdd           the mattpocock pack's tdd is the one agents get
  #   setup-pstack  pstack's own model setup; it writes Cursor rule files
  excluded = [ "tdd" "setup-pstack" ];

  # Linked under another name because a personal skill already has the upstream one.
  #   teach  the mattpocock pack's teach keeps the name
  renamed = { teach = "pstack-teach"; };

  upstream = "${pstack}/pstack";
  upstreamSkills = builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${upstream}/skills"));
  linkName = name: renamed.${name} or name;
  linked = map linkName (lib.subtractLists excluded upstreamSkills);

  # The upstream folder, plus a copy of each renamed skill whose frontmatter name matches
  # its new folder, and comment-sicko's prompt without frontmatter for opencode.
  tree = pkgs.runCommand "pstack-${pstack.shortRev}" { } ''
    cp -R ${upstream} $out
    chmod -R u+w $out
    ${lib.concatStrings (lib.mapAttrsToList (from: to: ''
      cp -R $out/skills/${from} $out/skills/${to}
      sed -i '0,/^name: ${from}$/s//name: ${to}/' $out/skills/${to}/SKILL.md
      grep -q '^name: ${to}$' $out/skills/${to}/SKILL.md
    '') renamed)}
    mkdir $out/opencode
    awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' \
      $out/agents/comment-sicko.md > $out/opencode/comment-sicko.md
  '';

  skillFiles = lib.concatMap (name: [
    { name = ".agents/skills/${name}"; value.source = "${tree}/skills/${name}"; }
    { name = ".claude/skills/${name}"; value.source = "${tree}/skills/${name}"; }
  ]) linked;
in

assert lib.assertMsg (lib.all (name: lib.elem name upstreamSkills) (excluded ++ lib.attrNames renamed))
  "pstack.nix: an excluded or renamed skill no longer exists upstream";
assert lib.assertMsg (lib.all (name: !(lib.elem name upstreamSkills)) (lib.attrValues renamed))
  "pstack.nix: a renamed skill's new name clashes with an upstream skill";

{
  home.file = lib.listToAttrs skillFiles // {
    ".claude/agents/comment-sicko.md".source = "${tree}/agents/comment-sicko.md";
    ".local/share/pstack".source = tree;
  };

  # home-manager would move an existing file aside (backupFileExtension) and link over it,
  # silently shadowing a personal skill that shares a pstack name. Stop instead.
  home.activation.pstackCheckClashes = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for target in ${lib.escapeShellArgs (map (f: f.name) skillFiles ++ [ ".claude/agents/comment-sicko.md" ])}; do
      path="$HOME/$target"
      if [ -e "$path" ] || [ -L "$path" ]; then
        case "$(readlink "$path" 2>/dev/null)" in
          /nix/store/*) ;;
          *)
            echo "pstack: $path already exists and isn't from pstack; add it to renamed or excluded in pstack.nix" >&2
            exit 1
            ;;
        esac
      fi
    done
  '';
}
