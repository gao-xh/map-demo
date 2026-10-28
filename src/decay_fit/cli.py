"""Command line: fit every run in a directory and print a table."""

import argparse

from decay_fit.fit import fit_decay
from decay_fit.load import load_runs


def main() -> None:
    parser = argparse.ArgumentParser(description="Fit decay times to every run in a directory.")
    parser.add_argument("directory", nargs="?", default="data/sample", help="directory of CSV runs")
    args = parser.parse_args()
    print(f"{'run':<8} {'tau (s)':>16} {'amplitude':>16} {'chi2/dof':>9}")
    for run in load_runs(args.directory):
        result = fit_decay(run)
        tau_text = f"{result.tau_s:.3f} ± {result.tau_err_s:.3f}"
        amplitude_text = f"{result.amplitude:.3f} ± {result.amplitude_err:.3f}"
        print(f"{result.run:<8} {tau_text:>16} {amplitude_text:>16} {result.reduced_chi2:>9.2f}")
