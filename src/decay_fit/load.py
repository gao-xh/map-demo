"""Load measurement runs from CSV files."""

from dataclasses import dataclass
from pathlib import Path

import numpy as np

COLUMNS = ("t_s", "signal", "sigma")


@dataclass(frozen=True)
class Run:
    """One measurement run: time in seconds, signal, and the signal's standard deviation."""

    name: str
    t_s: np.ndarray
    signal: np.ndarray
    sigma: np.ndarray


def load_run(path: Path) -> Run:
    """Load one CSV file with columns t_s, signal, sigma; drop rows with missing values.

    Raises:
        ValueError: if a column is missing or a sigma is not positive.
    """
    table = np.genfromtxt(path, delimiter=",", names=True, dtype=float)
    missing = [name for name in COLUMNS if name not in (table.dtype.names or ())]
    if missing:
        raise ValueError(f"{path}: missing columns {', '.join(missing)}")
    values = np.column_stack([table[name] for name in COLUMNS])
    # Drop NaN rows first so the fit doesn't fail
    values = values[~np.isnan(values).any(axis=1)]
    values = values[np.argsort(values[:, 0], kind="stable")]
    if np.any(values[:, 2] <= 0):
        raise ValueError(f"{path}: sigma must be positive")
    return Run(name=path.stem, t_s=values[:, 0], signal=values[:, 1], sigma=values[:, 2])


def load_runs(directory: str | Path) -> list[Run]:
    """Load every *.csv file in a directory, sorted by file name.

    Raises:
        FileNotFoundError: if the directory has no CSV files.
    """
    paths = sorted(Path(directory).glob("*.csv"))
    if not paths:
        raise FileNotFoundError(f"no CSV files in {directory}")
    return [load_run(path) for path in paths]
