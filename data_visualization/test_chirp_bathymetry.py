"""Tests chirp_bathymetry.py against the fixtures shared with the web and
mobile apps. Run from data_visualization/:  python -m pytest -q
(or without pytest:  python test_chirp_bathymetry.py)."""

import json
import math
from pathlib import Path

import chirp_bathymetry as cb

FIXTURES = Path(__file__).resolve().parent.parent / "test-fixtures" / "bathymetry"
EXPECTED = json.loads((FIXTURES / "expected.json").read_text())


def close(a, b, tol=1e-9):
    return math.isclose(a, b, rel_tol=0, abs_tol=tol)


def check(scan, exp):
    assert scan.total_rows == exp["totalRows"]
    assert scan.incomplete_rows == exp["incompleteRows"]
    assert scan.dropped_leading == exp["droppedLeading"]
    assert scan.dropped_trailing == exp["droppedTrailing"]
    assert scan.n == exp["used"]
    assert scan.times_ms[0] == exp["startMs"]
    assert scan.times_ms[-1] == exp["endMs"]
    st = cb.depth_stats(scan)
    assert close(st.mean_cm, exp["avgCm"])
    assert close(st.sd_cm, exp["sdCm"])
    assert close(st.min_cm, exp["minCm"])
    assert close(st.max_cm, exp["maxCm"])
    settled, n = cb.settled_depth(scan)
    assert close(settled, exp["settledCm"])
    assert n == exp["settledN"]


def test_settled_window_matches_apps():
    assert cb.SETTLED_WINDOW_S == EXPECTED["settledWindowS"]


def test_fixtures():
    for name, exp in EXPECTED["files"].items():
        check(cb.read_bathymetry(FIXTURES / name), exp)


def test_blind_spot_offset():
    check(
        cb.read_bathymetry(FIXTURES / "headerless.csv", blind_spot_offset_cm=5),
        EXPECTED["files"]["headerless.csv"]["blindSpotOffset5"],
    )


def test_rejects_bad_files():
    for name, fragment in EXPECTED["errors"].items():
        try:
            cb.read_bathymetry(FIXTURES / name)
        except cb.BathymetryFormatError as e:
            assert fragment in str(e), (name, str(e))
        else:
            raise AssertionError(f"{name} was not rejected")


def test_folder_names():
    assert cb.parse_folder_name("scan_data_7_deg_12_cm") == (7.0, 12.0)
    assert cb.parse_folder_name("scan_data_7.5_deg_0_cm") == (7.5, 0.0)
    assert cb.parse_folder_name("scan_data_dredging_site") == (None, None)


if __name__ == "__main__":
    for fn in [v for k, v in dict(globals()).items() if k.startswith("test_")]:
        fn()
    print("all tests passed")
