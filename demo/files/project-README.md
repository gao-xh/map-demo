# decay-fit

Fit exponential decay times, with one-sigma uncertainties, to measurement runs.

```sh
uv run decay-fit data/sample      # fit every run and print a table
uv run pytest -q                  # tests
uv run python scripts/make_sample_data.py   # regenerate the synthetic sample runs
```

The sample runs in `data/sample/` are synthetic (fixed seed): single exponential decays
with known noise, so the tests can compare the fit with the true decay times.

This project is built by a team of AI agents that follow the Multi-Agent Protocol; see
`AGENTS.md` for the roles.
