"""Write the synthetic sample runs in data/sample/ (fixed seed, so the files are reproducible).

Each run is an exponential decay signal = amplitude * exp(-t / tau) plus Gaussian noise of
known standard deviation sigma. A few rows are left empty, as a real instrument export
sometimes has them.

Usage: uv run python scripts/make_sample_data.py [output-directory]
"""

import sys
from pathlib import Path

import numpy as np

SEED = 20261028
NOISE_SIGMA = 0.02
# Run name -> (amplitude, true decay time in seconds)
RUNS = {
    "run-01": (1.00, 2.0),
    "run-02": (0.80, 3.5),
    "run-03": (1.20, 5.0),
}


def write_run(path: Path, amplitude: float, tau_s: float, rng: np.random.Generator) -> None:
    """Write one run as CSV with columns t_s, signal, sigma."""
    t_s = np.linspace(0.0, 20.0, 81)
    signal = amplitude * np.exp(-t_s / tau_s) + rng.normal(0.0, NOISE_SIGMA, t_s.size)
    lines = ["t_s,signal,sigma"]
    for index, (t_value, s_value) in enumerate(zip(t_s, signal)):
        # Every 20th row has a missing signal value
        signal_text = "" if index % 20 == 7 else f"{s_value:.6f}"
        lines.append(f"{t_value:.3f},{signal_text},{NOISE_SIGMA:.3f}")
    path.write_text("\n".join(lines) + "\n")


def main() -> None:
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data/sample")
    output_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    for name, (amplitude, tau_s) in RUNS.items():
        write_run(output_dir / f"{name}.csv", amplitude, tau_s, rng)
    print(f"wrote {len(RUNS)} runs to {output_dir}")


if __name__ == "__main__":
    main()
