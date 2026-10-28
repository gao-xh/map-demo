"""Fit an exponential decay to a run, with parameter uncertainties."""

from dataclasses import dataclass

import numpy as np
from scipy.optimize import curve_fit

from decay_fit.load import Run

MIN_POINTS = 5


@dataclass(frozen=True)
class DecayFit:
    """Fit result for signal = amplitude * exp(-t / tau), with one-sigma uncertainties."""

    run: str
    amplitude: float
    amplitude_err: float
    tau_s: float
    tau_err_s: float
    reduced_chi2: float


def decay_model(t_s: np.ndarray, amplitude: float, tau_s: float) -> np.ndarray:
    """Single exponential decay."""
    return amplitude * np.exp(-t_s / tau_s)


def fit_decay(run: Run) -> DecayFit:
    """Weighted least-squares fit of the decay model to one run.

    Uncertainties come from the covariance matrix with absolute sigma, so they are only as
    good as the sigma column of the data.

    Raises:
        ValueError: if the run has fewer than MIN_POINTS points.
    """
    if run.t_s.size < MIN_POINTS:
        raise ValueError(f"{run.name}: {run.t_s.size} points, need at least {MIN_POINTS}")
    # Start from the first signal value and a decay time of a third of the time span
    p0 = [float(run.signal[0]), float(np.ptp(run.t_s)) / 3.0]
    params, covariance = curve_fit(
        decay_model, run.t_s, run.signal, p0=p0, sigma=run.sigma, absolute_sigma=True
    )
    errors = np.sqrt(np.diag(covariance))
    residuals = (run.signal - decay_model(run.t_s, *params)) / run.sigma
    reduced_chi2 = float(np.sum(residuals**2) / (run.t_s.size - len(params)))
    return DecayFit(
        run=run.name,
        amplitude=float(params[0]),
        amplitude_err=float(errors[0]),
        tau_s=float(params[1]),
        tau_err_s=float(errors[1]),
        reduced_chi2=reduced_chi2,
    )
