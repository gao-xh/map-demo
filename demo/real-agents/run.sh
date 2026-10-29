#!/bin/sh
# Run the decay-fit story with real agents: Codex and Claude Code sessions, started one
# after another, each in its own clone, each reading its inbox and acting on its own.
#
# Usage: demo/real-agents/run.sh [WORKDIR]
#   CLAUDE  Claude Code command (default: claude, or ~/.local/bin/claude)
#   CODEX   Codex command (default: codex, or the one inside the ChatGPT app on macOS)
#
# Unlike demo/replay.sh, the agents write the code and the messages themselves, so every
# run differs and costs model usage. Each agent's output is kept in WORKDIR/logs/.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
work=${1:-$(mktemp -d "${TMPDIR:-/tmp}/map-real.XXXXXX")}

find_command() {  # find_command <name> <fallback path>: print a usable command or nothing
    if command -v "$1" >/dev/null 2>&1; then command -v "$1"; elif [ -x "$2" ]; then printf '%s\n' "$2"; fi
}
CLAUDE=${CLAUDE:-$(find_command claude "$HOME/.local/bin/claude")}
CODEX=${CODEX:-$(find_command codex "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")}
[ -n "$CLAUDE" ] || { echo "run.sh: Claude Code not found; set CLAUDE" >&2; exit 2; }
[ -n "$CODEX" ] || { echo "run.sh: Codex not found; set CODEX" >&2; exit 2; }

"$here/../replay.sh" --setup-only "$work"
# shellcheck disable=SC1091
. "$work/env.sh"
mkdir -p "$work/logs"

turn=0
agent() {  # agent <claude|codex> <clone> <prompt file>: one unattended session
    turn=$((turn + 1))
    log="$work/logs/$turn-$2-$1.log"
    prompt=$(cat "$here/prompts/common.md"; printf '\n'; cat "$here/prompts/$3")
    printf '\n\033[1m== %d. %s in %s/ (%s)\033[0m\n' "$turn" "$1" "$2" "$3"
    cd "$work/$2"
    case $1 in
        # Only the commands the protocol needs: git, the MAP scripts and the tests.
        # Tools not listed here are refused in -p mode, so nothing else can run.
        claude) "$CLAUDE" -p "$prompt" --permission-mode default \
                    --allowedTools "Read" "Edit" "Write" "Glob" "Grep" \
                    "Bash(git *)" "Bash(./tools/multi-agent-protocol/scripts/*)" \
                    "Bash(uv run --locked *)" > "$log" 2>&1 ;;
        # workspace-write keeps .git read-only; make this clone's .git writable
        # (adapters/codex.md in MAP). The remote is a local directory, so no network.
        codex) "$CODEX" exec -C "$work/$2" -s workspace-write --add-dir "$work" \
                    -c "sandbox_workspace_write.writable_roots=[\"$work/$2/.git\"]" \
                    --ephemeral -o "$log.last" "$prompt" > "$log" 2>&1 ;;
    esac || echo "   (the agent exited with status $?; see $log)"
    tail -n 25 "$log" | sed 's/^/   /'
}

agent codex data data.md
agent claude fit fit.md
agent claude lead lead.md
agent codex review review.md

# Review loop: fit either asks for the release or fixes the findings and asks for a new
# review, which the lead arranges. At most three reviews in all.
release_requested() {
    git -C "$work/lead" fetch --quiet origin coordination
    git -C "$work/lead" ls-tree --name-only origin/coordination messages/ | grep -q '_release-request\.md$'
}
round=1
while :; do
    agent claude fit fit-release.md
    release_requested && break
    [ "$round" -lt 3 ] || { echo "   no release-request after $round reviews; stopping before release"; break; }
    round=$((round + 1))
    agent claude lead lead.md
    agent codex review review.md
done
release_requested && agent claude release release.md

cd "$work/lead"
git fetch --quiet origin
printf '\n\033[1m== Result\033[0m\n'
echo "   main:"; git log --oneline --format='     %h %an: %s' origin/main
echo "   messages:"; git ls-tree --name-only origin/coordination messages/ | grep -v gitkeep | sed 's/^/     /'
./tools/multi-agent-protocol/scripts/doctor.sh 2>&1 | sed 's/^/   /' || true
echo
echo "Work directory: $work (agent output in logs/)"
