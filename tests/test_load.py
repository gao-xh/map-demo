from pathlib import Path

import numpy as np
import pytest

from decay_fit.load import load_run, load_runs

SAMPLE_DIR = Path(__file__).resolve().parents[1] / "data" / "sample"


def test_loads_every_sample_run_in_name_order():
    runs = load_runs(SAMPLE_DIR)
    assert [run.name for run in runs] == ["run-01", "run-02", "run-03"]


def test_columns_have_equal_length():
    for run in load_runs(SAMPLE_DIR):
        assert run.t_s.size == run.signal.size == run.sigma.size


def test_rows_with_missing_values_are_dropped():
    run = load_run(SAMPLE_DIR / "run-01.csv")
    assert run.t_s.size == 77
    assert not np.isnan(run.signal).any()


def test_rows_are_sorted_by_time(tmp_path):
    path = tmp_path / "unsorted.csv"
    path.write_text("t_s,signal,sigma\n2,0.5,0.1\n0,1.0,0.1\n1,0.7,0.1\n")
    assert load_run(path).t_s.tolist() == [0.0, 1.0, 2.0]


def test_missing_column_is_an_error(tmp_path):
    path = tmp_path / "bad.csv"
    path.write_text("t_s,signal\n0,1.0\n")
    with pytest.raises(ValueError, match="missing columns sigma"):
        load_run(path)


def test_non_positive_sigma_is_an_error(tmp_path):
    path = tmp_path / "bad.csv"
    path.write_text("t_s,signal,sigma\n0,1.0,0\n")
    with pytest.raises(ValueError, match="sigma must be positive"):
        load_run(path)


def test_empty_directory_is_an_error(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_runs(tmp_path)
