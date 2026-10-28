from pathlib import Path

import numpy as np
import pytest

from decay_fit.fit import fit_decay
from decay_fit.load import Run, load_run

SAMPLE_DIR = Path(__file__).resolve().parents[1] / "data" / "sample"
# True decay times used by scripts/make_sample_data.py
TRUE_TAU_S = {"run-01": 2.0, "run-02": 3.5, "run-03": 5.0}


@pytest.mark.parametrize("name", sorted(TRUE_TAU_S))
def test_recovers_the_true_decay_time_within_three_sigma(name):
    result = fit_decay(load_run(SAMPLE_DIR / f"{name}.csv"))
    assert abs(result.tau_s - TRUE_TAU_S[name]) < 3 * result.tau_err_s


def test_uncertainties_are_positive_and_chi2_is_reasonable():
    result = fit_decay(load_run(SAMPLE_DIR / "run-03.csv"))
    assert result.tau_err_s > 0 and result.amplitude_err > 0
    assert 0.5 < result.reduced_chi2 < 1.5


def test_too_few_points_is_an_error():
    run = Run(name="short", t_s=np.arange(3.0), signal=np.ones(3), sigma=np.ones(3))
    with pytest.raises(ValueError, match="need at least"):
        fit_decay(run)
