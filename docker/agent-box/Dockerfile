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
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# uid 501 matches the macOS first user, so files on colima's virtiofs share of
# $HOME stay readable/writable.
RUN useradd --create-home --shell /bin/bash --uid 501 agent
USER agent
WORKDIR /home/agent

ENTRYPOINT ["pi"]
