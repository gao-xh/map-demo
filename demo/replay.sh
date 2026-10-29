#!/bin/sh
# Replay a MAP team building the decay-fit example, step by step, in a fresh directory.
#
# Usage: demo/replay.sh [--map DIR] [--pause] [WORKDIR]
#   --map DIR  use this checkout of multi-agent-protocol instead of cloning the public
#              repository at the tag in MAP_TAG (default v2.0.0)
#   --pause    wait for Enter after each step (for recordings and live demos)
#   --setup-only  stop after the lead has handed out the work (step 3), with one clone
#              per session and an env.sh to source; used by demo/real-agents/run.sh
#   WORKDIR    empty or new directory for the run (default: a new temporary directory)
#
# Every agent action is a fixed shell command, so a run is reproducible: the commits on the
# development branches get the same SHAs on every machine (fixed names, dates and file
# contents). Coordination messages carry the real time of the run, so their file names and
# the coordination branch's SHAs differ between runs.
#
# Needs: git, uv (the tests run with `uv run --locked pytest`), network access for the first
# uv run and for cloning MAP (unless --map is given).
set -eu

MAP_TAG=${MAP_TAG:-v2.0.0}
MAP_URL=${MAP_URL:-https://github.com/gao-xh/multi-agent-protocol}
demo_root=$(cd "$(dirname "$0")/.." && pwd)
map_dir=""
pause=0
setup_only=0
while [ $# -gt 0 ]; do
    case $1 in
        --map) map_dir=$(cd "$2" && pwd); shift 2 ;;
        --pause) pause=1; shift ;;
        --setup-only) setup_only=1; shift ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "replay.sh: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
work=${1:-$(mktemp -d "${TMPDIR:-/tmp}/map-demo.XXXXXX")}
mkdir -p "$work"
work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "replay.sh: $work is not empty" >&2; exit 2; }
command -v uv >/dev/null 2>&1 || { echo "replay.sh: uv is required (https://docs.astral.sh/uv/)" >&2; exit 2; }

# Isolate git from the user's own configuration (hooks, signing, default branch).
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$work/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false
export MAP_UPDATE_SECONDS=0   # no release-check network call from the scripts
# One Python environment for every session, so numpy and scipy install once
export UV_PROJECT_ENVIRONMENT="$work/venv"

step_number=0
step() {   # step <title>: print a step heading, and pause when asked
    step_number=$((step_number + 1))
    printf '\n\033[1m== %d. %s\033[0m\n' "$step_number" "$1"
    if [ "$pause" -eq 1 ]; then printf '   (Enter to run) '; read -r _; fi
}
quiet() {    # quiet <command>: run it, and show its output only when it fails
    if ! "$@" > "$work/last-command.log" 2>&1; then cat "$work/last-command.log" >&2; exit 1; fi
}
say() { printf '   %s\n' "$*"; }
run() { printf '   $ %s\n' "$*"; "$@" 2>&1 | sed 's/^/     /'; }
refused() {  # refused <command>: run a command that should fail, and show its exit status
    printf '   $ %s\n' "$*"
    if "$@" > "$work/last-command.log" 2>&1; then
        sed 's/^/     /' "$work/last-command.log"; say "expected a refusal, got exit 0"; exit 1
    else
        status_code=$?
        sed 's/^/     /' "$work/last-command.log"; say "(exit $status_code)"
    fi
}
at() {     # at <ISO time>: the clock for the commits that follow
    export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"
}
session() {  # session <line> [<directory name>]: clone the project as that line
    dir="$work/${2:-$1}"
    git clone --quiet "$work/origin.git" "$dir" 2>/dev/null
    git -C "$dir" config user.name "$1"
    git -C "$dir" config user.email "$1@decay-fit.invalid"
}
in_session() { cd "$work/$1"; }
map() { script=$1; shift; "./tools/multi-agent-protocol/scripts/$script.sh" "$@"; }
status() {   # status <line> <role> <branch> <task> <area> <state> <agent> <machine>
    cat > "$work/status-$1.md" <<EOF
# Status: $1

- Role: $2
- Branch: $3
- Task: $4
- Area: $5
- State: $6
- Last-read: <keep>
- Updated: placeholder

## Environment

- Protocol: placeholder
- Agent: $7 (simulated by demo/replay.sh)
- Model: unknown
- Machine: $8
- Sandbox: workspace-write; network: yes
- Can run: uv run --locked pytest
- Cannot: advance main (except release)
- Reachable by: coordination branch only; checks the inbox at session start
- Wake: none (the replay runs each step in order)
- Pushes coordination branch: yes
- Owner present: sometimes
- Git identity: $1
EOF
    quiet map status "$1" "$work/status-$1.md"
}
send() {     # send <file>: send a message and print its path
    map send "$1"
}
show() {     # show <message path>: print a message from the coordination branch
    git fetch --quiet origin coordination
    printf '   $ git show origin/coordination:%s\n' "$1"
    git show "origin/coordination:$1" | sed 's/^/     /'
}
tests() {    # tests <pytest args>: run the tests and print pytest's summary line
    uv run --quiet --locked pytest -q "$@" 2>&1 | tail -n 1 | sed 's/ in [0-9.]*s$//'
}

echo "MAP demo: decay-fit, built by a team of simulated agents"
echo "Work directory: $work"

# ---------------------------------------------------------------------------
step "The owner starts the project: sample data and an empty package"
at "2026-11-02T09:00:00Z"
git init --quiet --bare "$work/origin.git"
session owner
in_session owner
mkdir -p src/decay_fit scripts data
cp "$demo_root/demo/files/project-README.md" README.md
cp "$demo_root/pyproject.toml" "$demo_root/uv.lock" "$demo_root/.python-version" "$demo_root/.gitignore" .
cp "$demo_root/src/decay_fit/__init__.py" src/decay_fit/
cp "$demo_root/scripts/make_sample_data.py" scripts/
cp -R "$demo_root/data/sample" data/
git add -A
git commit --quiet -m "chore: start the decay-fit project"
git push --quiet origin main
run git log --oneline -1

# ---------------------------------------------------------------------------
step "The lead sets up MAP: rules in AGENTS.md, the coordination branch, its status"
at "2026-11-02T09:05:00Z"
if [ -z "$map_dir" ]; then
    quiet git clone --quiet --depth 1 --branch "$MAP_TAG" "$MAP_URL" "$work/map-src"
    map_dir="$work/map-src"
fi
session lead
in_session lead
quiet "$map_dir/scripts/install.sh" "$work/lead"
# install.sh records the install time; use the replay's clock so the commit is reproducible
sed -i.bak "s/^Installed: .*/Installed: $GIT_COMMITTER_DATE/" tools/multi-agent-protocol/VERSION
rm tools/multi-agent-protocol/VERSION.bak
cp "$demo_root/demo/files/AGENTS.md" AGENTS.md
git add -A
git commit --quiet -m "chore: adopt the Multi-Agent Protocol"
git push --quiet origin main
quiet map init-coordination
status lead lead main "plan the decay fit" "AGENTS.md, shared contracts" building "Claude Code" "mac; macOS"
run git log --oneline -1
say "Role table (AGENTS.md):"
sed -n '/^| Line | Role/,/^$/p' AGENTS.md | sed 's/^/     /'

# ---------------------------------------------------------------------------
step "The lead hands out the work: the loader to line data, the fit to line fit"
cat > "$work/to-data.md" <<'EOF'
type: handover
from: lead
to: data

## Goal
Load every measurement run in data/sample into arrays t_s, signal and sigma, dropping rows
with missing values, so that line fit can fit decay times.

## Current state
- Branch: main (pushed: yes)
- Code changed so far: none

## Confirmed facts
- Each CSV file in data/sample has the header t_s,signal,sigma; some rows have an empty signal

## Suggested approach
- src/decay_fit/load.py: load_run(path) -> Run, load_runs(directory) -> list[Run]

## Blockers and decisions needed
- none

## Done means
- Tests: tests/test_load.py covers missing values, sorting, a missing column, sigma <= 0
- Docs: docstrings
- Report back with: branch, SHA, checks run and results; hand the loader to fit
EOF
cat > "$work/to-fit.md" <<'EOF'
type: handover
from: lead
to: fit

## Goal
Fit a decay time with its uncertainty for every run, on top of line data's loader.

## Current state
- Branch: none yet; start from data's branch when data hands over
- Code changed so far: none

## Confirmed facts
- The sample runs are single exponential decays with known noise (scripts/make_sample_data.py)

## Suggested approach
- src/decay_fit/fit.py: fit_decay(run) with scipy curve_fit, absolute sigma; a small CLI

## Blockers and decisions needed
- Waits for data's loader handover

## Done means
- Tests: tests/test_fit.py recovers the true decay times within three sigma
- Report back with: branch, SHA, checks run and results; ask review, then release
EOF
to_data=$(send "$work/to-data.md")
to_fit=$(send "$work/to-fit.md")
say "sent $to_data"
say "sent $to_fit"

if [ "$setup_only" -eq 1 ]; then
    in_session lead
    # Fill the shared environment and a cache inside the work directory while the network
    # is on, so that sandboxed agents can run the tests offline
    UV_CACHE_DIR="$work/uv-cache" quiet uv sync --quiet --locked
    for line in data fit review release; do session "$line"; done
    cat > "$work/env.sh" <<EOF
# Source this before running an agent in one of the session clones.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$work/gitconfig"
export MAP_UPDATE_SECONDS=0
export UV_PROJECT_ENVIRONMENT="$work/venv"
export UV_CACHE_DIR="$work/uv-cache"
export UV_OFFLINE=1
EOF
    cat <<EOF

Set up. The lead has handed out the work; nothing is built yet.
  origin.git                      the shared remote
  lead/ data/ fit/ review/ release/   one clone per session, each with its git identity
  env.sh                          source it before starting an agent in a clone
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
step "Line data (Codex) joins, claims the task and builds the loader"
at "2026-11-02T09:20:00Z"
session data
in_session data
status data line data/loader "load-runs: the loader (handover from lead)" "src/decay_fit/load.py, tests/test_load.py" building "Codex" "mac; macOS"
run map inbox data
run map claim --branch data/loader data load-runs
git switch --quiet -c data/loader
cp "$demo_root/src/decay_fit/load.py" src/decay_fit/
mkdir -p tests
cp "$demo_root/tests/test_load.py" tests/
git add -A
git commit --quiet -m "feat: load measurement runs from CSV files"
data_tests=$(tests tests/test_load.py)
git push --quiet origin data/loader
data_sha=$(git rev-parse HEAD)
say "tests: $data_tests"
say "pushed data/loader at $data_sha"

# ---------------------------------------------------------------------------
step "Line fit starts early and tries the same task: the claim is refused"
at "2026-11-02T09:40:00Z"
session fit
in_session fit
refused map claim --branch fit/decay fit load-runs
say "fit waits for data's handover instead of building a second loader"

# ---------------------------------------------------------------------------
step "Line data hands the loader to line fit, with the exact commit and the tests it ran"
in_session data
cat > "$work/data-to-fit.md" <<EOF
type: handover
from: data
to: fit
refs: $to_data

## Goal
Fit a decay time with its uncertainty for every run, using the new loader.

## Current state
- Branch: data/loader at $data_sha (pushed: yes)
- Code changed so far: src/decay_fit/load.py, tests/test_load.py

## Confirmed facts
- load_runs("data/sample") returns one Run per file with arrays t_s, signal, sigma
- Rows with missing values are dropped; tested with tests/test_load.py ($data_tests)

## Suggested approach
- Branch from data/loader at the SHA above

## Blockers and decisions needed
- none

## Done means
- Tests: tests/test_fit.py recovers the known decay time of data/sample/run-03.csv
- Report back with: branch, SHA, checks run and results
EOF
data_handover=$(send "$work/data-to-fit.md")
say "sent $data_handover"
run map release-claim data load-runs
quiet map mark-read data "$to_data"
show "$data_handover"

# ---------------------------------------------------------------------------
step "Line fit (Claude Code) joins, claims the fit and starts on data's commit"
at "2026-11-02T10:00:00Z"
in_session fit
status fit line fit/decay "decay-fit: the decay fit (handovers from lead and data)" "src/decay_fit/fit.py, src/decay_fit/cli.py, tests/test_fit.py" building "Claude Code" "mac; macOS"
run map inbox fit
run map claim --branch fit/decay fit decay-fit
git switch --quiet -c fit/decay "$data_sha"
cp "$demo_root/src/decay_fit/fit.py" src/decay_fit/
git add -A
git commit --quiet -m "WIP: fit a single exponential decay"
git push --quiet origin fit/decay
fit_wip_sha=$(git rev-parse HEAD)
say "pushed fit/decay at $fit_wip_sha (WIP: no tests yet)"

# ---------------------------------------------------------------------------
step "The fit session runs out of context: it leaves a transfer handover and ends"
cat > "$work/fit-transfer.md" <<EOF
type: handover
from: fit
to: fit
refs: $data_handover

## Transfer of line fit

- From: Claude Code, mac
- To: Codex, laptop
- Reason: the session ran out of context

## Branches (all pushed; no uncommitted changes or stashes)

- fit/decay at $fit_wip_sha (WIP)

## Current task

- Task and claim: decay-fit (claims/decay-fit.md)
- Done so far: src/decay_fit/fit.py: fit_decay(run) with curve_fit and absolute sigma
- Next step: add tests/test_fit.py (true decay times within three sigma) and the CLI

## Not handled yet

- Messages: $to_fit, $data_handover
- Promised to others: none

## Only on the old machine

- nothing

## Tried and failed

- none
EOF
transfer=$(send "$work/fit-transfer.md")
sed -i.bak 's/^- State: .*/- State: transferring to Codex, laptop/' "$work/status-fit.md"
rm "$work/status-fit.md.bak"
quiet map status fit "$work/status-fit.md"
say "sent $transfer"

# ---------------------------------------------------------------------------
step "A new fit session (Codex, another machine) reads the transfer and checks every SHA"
at "2026-11-02T10:30:00Z"
session fit fit-laptop
in_session fit-laptop
run map inbox fit
show "$transfer"
expected=$(sed -n 's/^- fit\/decay at \([0-9a-f]*\).*/\1/p' "$work/fit-transfer.md")
git fetch --quiet origin
actual=$(git rev-parse origin/fit/decay)
if [ "$expected" = "$actual" ]; then say "fit/decay is at $actual, as the transfer says"; else
    say "fit/decay is at $actual, the transfer says $expected: stop and ask the owner"; exit 1; fi
status fit line fit/decay "decay-fit: continue from the transfer" "src/decay_fit/fit.py, src/decay_fit/cli.py, tests/test_fit.py" building "Codex" "laptop; macOS"
run map claim --branch fit/decay fit decay-fit
git switch --quiet fit/decay
cp "$demo_root/src/decay_fit/cli.py" src/decay_fit/
cp "$demo_root/tests/test_fit.py" tests/
git add -A
git commit --quiet -m "feat: decay fit with uncertainties, tests and command line"
fit_tests=$(tests)
git push --quiet origin fit/decay
fit_sha=$(git rev-parse HEAD)
for message in "$to_fit" "$data_handover" "$transfer"; do quiet map mark-read fit "$message"; done
status fit line fit/decay "decay-fit: fit/decay at $fit_sha, ready for review" "src/decay_fit/fit.py, src/decay_fit/cli.py, tests/test_fit.py" "in review" "Codex" "laptop; macOS"
say "tests: $fit_tests"
say "pushed fit/decay at $fit_sha"
run uv run --quiet --locked decay-fit data/sample

# ---------------------------------------------------------------------------
step "The lead asks an agent that did not build it to review that exact commit"
at "2026-11-02T11:00:00Z"
in_session lead
run map status fit
cat > "$work/review-request.md" <<EOF
type: handover
from: lead
to: review
refs: $transfer

## Goal
Review fit/decay at $fit_sha (the loader from data and the fit).

## Current state
- Branch: fit/decay at $fit_sha (pushed: yes)
- Code changed so far: src/decay_fit/load.py, fit.py, cli.py, tests/

## Confirmed facts
- uv run --locked pytest -q: $fit_tests

## Suggested approach
- Check that the uncertainties use absolute sigma and that the tests compare with true values

## Blockers and decisions needed
- none

## Done means
- Tests: rerun the tests on that commit
- Report back with: a review message for that SHA
EOF
review_request=$(send "$work/review-request.md")
session review
in_session review
status review line none "review of fit/decay" "review only" building "Claude Code" "mac; macOS"
git switch --quiet --detach "$fit_sha"
review_tests=$(tests)
cat > "$work/review.md" <<EOF
type: review
from: review
to: lead, fit
refs: $review_request

Reviewed: fit/decay at $fit_sha
Earlier findings: none

## P1 (blocks release)
- none

## P2 (fix before release)
- none

## P3 (fix when convenient)
- fit_decay has no offset term; a run with a baseline would bias tau | expected: a note in the docstring | evidence: src/decay_fit/fit.py decay_model

## Looked good
- uv run --locked pytest -q on $fit_sha: $review_tests
- curve_fit uses absolute_sigma=True; tests compare with the true decay times of the generator

## Only simulated or not checked
- real instrument data
EOF
review=$(send "$work/review.md")
quiet map mark-read review "$review_request"
say "sent $review"
show "$review"

# ---------------------------------------------------------------------------
step "Line fit asks for the release"
in_session fit-laptop
cat > "$work/release-request.md" <<EOF
type: release-request
from: fit
to: release
refs: $review

- Branch: fit/decay
- Commit: $fit_sha (merged with main at $(git rev-parse origin/main): yes, main is its ancestor)
- Migrations: none
- Configuration, secrets or scheduled-job changes: none
- Reviews: $review reviewed $fit_sha (no P1 or P2)
- Owner approvals: none needed to merge into main; the release tag v0.1.0 needs the owner (AGENTS.md)
- What it changes: loader for measurement runs; decay fit with uncertainties; decay-fit command
- Interfaces changed: none (new modules only)
- Checks run: uv run --locked pytest -q: $fit_tests
- Known limits: sample data only; no offset term (review P3)
EOF
release_request=$(send "$work/release-request.md")
say "sent $release_request"
run map release-claim fit decay-fit

# ---------------------------------------------------------------------------
step "Release merges into main only after the checks pass on that exact commit"
at "2026-11-02T11:30:00Z"
session release
in_session release
status release release main "release decay fit" "main" building "Claude Code" "mac; macOS"
run map claim --hours 1 --branch main release release-main
git fetch --quiet origin
[ "$(git rev-parse origin/fit/decay)" = "$fit_sha" ] || { say "fit/decay moved since the request: stop"; exit 1; }
git switch --quiet --detach "$fit_sha"
release_tests=$(tests)
say "tests on $fit_sha: $release_tests"
git switch --quiet main
git merge --quiet --ff-only "$fit_sha"
git push --quiet origin main
main_sha=$(git rev-parse HEAD)
say "main is at $main_sha"

# ---------------------------------------------------------------------------
step "The tag needs you: release asks, you answer in its session, release records it"
at "2026-11-02T11:40:00Z"
say "release: May I tag main at $main_sha as v0.1.0? The checks passed on that commit."
if [ "$pause" -eq 1 ]; then
    printf '   You (y/N): '; read -r owner_answer
else
    owner_answer=y; say "You: y (answered by the replay; run with --pause to answer yourself)"
fi
case $owner_answer in y|Y|yes) ;; *) say "no approval: release stops here, main stays untagged"; exit 0 ;; esac
cat > "$work/decision-tag.md" <<EOF
# Tag v0.1.0

Date: 2026-11-02. Given directly in the release session.

The owner approved the release tag, in these words: "y" (answer to: "May I tag main at
$main_sha as v0.1.0?").

Approved: main at $main_sha

Scope: the annotated tag v0.1.0 on that commit. Exclusions: any other tag or commit.
EOF
decision=$(map decide owner-tag-v0.1.0 "$work/decision-tag.md" 2>&1 | sed -n 's/.*\(decisions\/[^ ]*\.md\).*/\1/p' | head -n 1)
say "recorded ${decision:-the decision}"
git tag -a v0.1.0 -m "decay-fit 0.1.0" "$main_sha"
git push --quiet origin v0.1.0
run git tag -n1 v0.1.0
cat > "$work/released.md" <<EOF
type: released
from: release
to: fit, lead, all
refs: $release_request

- Production: $main_sha (no deployment in this project)
- Main branch: $main_sha
- Tag: v0.1.0 (owner approval: ${decision:-decisions/})
- Went live: loader, decay fit, decay-fit command
- Migrations: none
- Checks: uv run --locked pytest -q on $fit_sha: $release_tests
- Backup: not needed (fast-forward)
- Rollback: git revert --no-edit $data_sha^..$main_sha
- Follow-ups for the requester: none
EOF
released=$(send "$work/released.md")
quiet map mark-read release "$release_request"
run map release-claim release release-main
say "sent $released"

# ---------------------------------------------------------------------------
step "What the coordination branch holds now"
in_session lead
git fetch --quiet origin
run git ls-tree -r --name-only origin/coordination
run map doctor
say "main:"
git log --oneline --format='%h %an: %s' origin/main | sed 's/^/     /'

cat <<EOF

Done. Everything is in $work:
  origin.git    the shared remote (main, data/loader, fit/decay, coordination)
  lead/ data/ fit/ fit-laptop/ review/ release/   one clone per session
  venv/         the Python environment all sessions share
Commits:
  data/loader  $data_sha
  fit/decay    $fit_sha
  main         $main_sha
EOF
