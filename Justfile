# The checks and jobs of this repository's automation. Workflows call these
# recipes rather than inline scripts, so a check runs the same here and in CI.

# Recipes see their arguments as $1, $2, ...
set positional-arguments

# Every test of the scripts under .github.
test: test-poll test-usage

test-poll:
    cd .github/poll && node --test

# usage.cjs is here only for the coordinator, which reads a usage snapshot
# with it; nothing publishes one yet.
test-usage:
    cd .github/usage && node --test

coordinator *args:
    node .github/poll/coordinator.cjs "$@"

poll *args:
    node .github/poll/poll.cjs "$@"

# agent-board at the commit .github/poll/agent-board.json pins, never a
# branch head: the binary runs with the bot's token.
build-agent-board:
    #!/usr/bin/env bash
    set -euo pipefail
    source=$(jq -er .source .github/poll/agent-board.json)
    rev=$(jq -er .rev .github/poll/agent-board.json)
    [[ $rev =~ ^[0-9a-f]{40}$ ]]
    cargo install --locked --root "$RUNNER_TEMP/agent-board" --git "$source" --rev "$rev" agent-board
    echo "rev=$rev" >> "${GITHUB_OUTPUT:-/dev/null}"

# The shared workflow check that ci.yml's lint job calls, run locally from
# a checkout of jmarrero-forge/actions (its lint/README.md), the path
# relative to this repository's root; CONTAINER=podman without docker:
#   just lint ../actions
lint actions:
    {{ just_executable() }} --justfile "{{ actions }}/lint/Justfile" --working-directory . check
