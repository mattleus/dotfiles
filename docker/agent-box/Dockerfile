FROM node:22-slim

# gh has no Debian package; GitHub publishes its own apt repo, keyed by its
# archive keyring.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ripgrep curl ca-certificates \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && apt-get install -y --no-install-recommends openssh-server tmux zsh jq \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Herdr: exact pin mirroring fm-install-herdr.sh in the host firstmate repo -
# same official GitHub release asset, same SHA-256 policy (never a floating
# package-manager latest), plus the post-install version and protocol gates.
# TARGETARCH is set by buildkit (docker default); arm64 is the colima path.
ARG TARGETARCH
RUN set -eu; \
  case "$TARGETARCH" in \
    arm64) ASSET=herdr-linux-aarch64; SHA256=544e0002de42806d1ab64ccdef3a7e7414f24717b0b6b022bc9e57d2eefd26a2 ;; \
    amd64) ASSET=herdr-linux-x86_64;  SHA256=bc0fc02d4ba500f9cac2353a43e67fe036785ecca6eb55378e050fac3c103059 ;; \
    *) echo "unsupported TARGETARCH $TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL --max-filesize 25000000 \
    "https://github.com/ogulcancelik/herdr/releases/download/v0.7.4/$ASSET" \
    -o /tmp/herdr; \
  echo "$SHA256  /tmp/herdr" | sha256sum -c -; \
  install -m 0755 /tmp/herdr /usr/local/bin/herdr; \
  rm /tmp/herdr; \
  version="$(herdr --version | awk '{print $2; exit}')"; \
  [ "$version" = "0.7.4" ]; \
  protocol="$(herdr status --json | jq -r '.client.protocol // empty')"; \
  [ -n "$protocol" ] && [ "$protocol" -ge 16 ]

# The box shares the host fleet layout: agent's HOME is /Users/matt so paths
# spelled identically on the host (~/repos, ~/.pi/agent, ~/.treehouse, the
# ~/firstmate symlink into the firstmate checkout) resolve unchanged inside.
# uid 501 matches the macOS first user, so files on colima's virtiofs share of
# host $HOME stay readable/writable. Password '*' means no password login but
# the account is not locked, so ssh pubkey auth works. /Users/matt itself is
# container-local (never mounted); only the three boundary mounts land on it.
RUN install -d /Users \
 && useradd --create-home --home-dir /Users/matt --shell /usr/bin/zsh \
      --uid 501 --password '*' agent \
 && ln -s /Users/matt/repos/public/firstmate /Users/matt/firstmate

# no-mistakes and treehouse per their official install scripts, as the agent
# user, into ~/.local/bin (both scripts pick that prefix when it leads PATH,
# matching home.nix's installNoMistakes PATH wrap).
USER agent
ENV HOME=/Users/matt
RUN mkdir -p "$HOME/.local/bin" \
 && env PATH="$HOME/.local/bin:$PATH" sh -c \
      "curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh" \
 && env PATH="$HOME/.local/bin:$PATH" sh -c \
      "curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh"

# Shell seed: no-mistakes/treehouse on PATH, and land in the firstmate
# checkout (~/firstmate symlink) on login. Having a .zshrc at all suppresses
# zsh's first-run newuser wizard on ssh login.
RUN printf '%s\n' \
      'export PATH="$HOME/.local/bin:$PATH"' \
      '' \
      '# land in the firstmate checkout, as on the host' \
      'cd "$HOME/firstmate" 2>/dev/null || true' \
      > "$HOME/.zprofile" \
 && printf '%s\n' \
      'export PATH="$HOME/.local/bin:$PATH"' \
      > "$HOME/.zshrc"

USER root
COPY agentbox-init /usr/local/sbin/agentbox-init
RUN chmod 755 /usr/local/sbin/agentbox-init
USER agent

WORKDIR /Users/matt

ENTRYPOINT ["pi"]
