# MAP demo: a team of agents builds a decay fit

A reproducible demo of the [Multi-Agent Protocol](https://github.com/gao-xh/multi-agent-protocol)
(MAP): a lead and four other sessions build a small data-analysis feature together, in
plain git. One command replays the whole story in a fresh directory:

```sh
git clone https://github.com/gao-xh/map-demo
cd map-demo
demo/replay.sh            # add --pause to stop after each step
```

It needs `git` and [uv](https://docs.astral.sh/uv/), and takes about three minutes (most of
it is installing numpy and scipy once per session).

## The story

| Step | Session | What happens |
| --- | --- | --- |
| 1 | owner | starts the project: synthetic sample runs and an empty package |
| 2 | lead (Claude Code) | installs MAP, writes the role table into `AGENTS.md`, creates the `coordination` branch |
| 3 | lead | hands the loader to line `data` and the fit to line `fit` |
| 4 | data (Codex) | claims the task, builds `load_runs`, runs its tests, pushes `data/loader` |
| 5 | data | hands the loader to `fit` with the exact commit and the tests it ran |
| 6 | fit (Claude Code) | claims the fit and starts on data's commit |
| 7 | fit | runs out of context: pushes a WIP commit and leaves a `transfer` handover |
| 8 | fit (Codex, another machine) | reads the transfer, checks the branch SHA, finishes the fit and its tests |
| 9 | review | an agent that did not build it reviews that exact commit |
| 10 | fit | asks for the release |
| 11 | release | reruns the tests on that commit, then fast-forwards `main` |
| 12 | lead | `doctor.sh` checks the coordination branch: 0 errors, 0 warnings |

The agents are simulated: every action is a fixed shell command in
[`demo/replay.sh`](demo/replay.sh), so the run is the same every time. The commits on the
development branches get the same SHAs on every machine; coordination messages carry the
real time of the run, so their names differ. With real agents, each session follows the
same steps from `AGENTS.md` and the MAP scripts.

After a run, everything stays in the work directory the script prints: the shared remote
`origin.git` and one clone per session (`lead/`, `data/`, `fit/`, `fit-laptop/`,
`review/`, `release/`). Read the messages with
`git -C <work>/lead show origin/coordination:messages/<name>`.

## The example project

`decay-fit` fits exponential decay times, with one-sigma uncertainties, to measurement runs:

```sh
uv run decay-fit data/sample
uv run pytest -q
```

```
run               tau (s)        amplitude  chi2/dof
run-01      2.048 ± 0.039    0.990 ± 0.012      0.98
run-02      3.535 ± 0.066    0.789 ± 0.010      1.15
run-03      5.080 ± 0.054    1.195 ± 0.009      1.06
```

The sample runs are synthetic, written by `scripts/make_sample_data.py` with a fixed seed
(true decay times 2.0, 3.5 and 5.0 s), so the tests can check the fit against the truth.

## Files

- `demo/replay.sh`: the replay; `--map DIR` uses a local MAP checkout instead of cloning
  the public repository at `v2.0.0` (`MAP_TAG`)
- `demo/files/AGENTS.md`: the rules the lead writes, with the role table
- `demo/files/project-README.md`: the README of the replayed project
- `src/`, `tests/`, `data/sample/`, `scripts/`: the finished example project, which the
  replay adds step by step

License: MIT.
