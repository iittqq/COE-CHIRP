"""Checks that chirp_netcdf.py writes the same dataset as the web app.

test-fixtures/netcdf/header.nc is written by the web app's exporter
(chirp-control-web/src/utils/exportScanNetcdf.test.ts). This test writes the
same scan with the Python exporter, using the same parameters, and compares
dimensions, variables, types, attributes and values. Reading the golden file
with netCDF4 also independently checks the web app's NetCDF writer."""

from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from netCDF4 import Dataset

import chirp_bathymetry as cb
import chirp_netcdf as cn

FIXTURES = Path(__file__).resolve().parent.parent / "test-fixtures"


def attrs(obj):
    return {k: obj.getncattr(k) for k in obj.ncattrs()}


def same(a, b):
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    a, b = np.asarray(a), np.asarray(b)
    if a.dtype != b.dtype or a.shape != b.shape:
        return False
    # Last-bit differences between JavaScript and Python arithmetic are fine.
    return np.allclose(a, b, rtol=1e-12, atol=0) if a.dtype.kind == "f" else np.array_equal(a, b)


def test_python_export_matches_web_golden(tmp_path):
    scan = cb.read_bathymetry(FIXTURES / "bathymetry" / "header.csv", blind_spot_offset_cm=2)
    out = cn.write_scan_netcdf(
        tmp_path / "header.nc", scan,
        title="header fixture", scan_id="fixture-0001", folder_name="header",
        acquisition={"sonarModel": "Deeper CHIRP+ 2", "scanAngleDeg": 7, "transducerElevationM": 1.25,
                     "datum": "NAVD88 (GEOID18)", "blindSpotOffsetCm": 2},
        sonar_csv=FIXTURES / "bathymetry" / "header_sonar.csv",
        software="chirp-control-web golden",
        exported_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    with Dataset(FIXTURES / "netcdf" / "header.nc") as web, Dataset(out) as py:
        assert web.file_format == py.file_format == "NETCDF3_CLASSIC"
        assert {k: len(d) for k, d in web.dimensions.items()} == {k: len(d) for k, d in py.dimensions.items()}

        wa, pa = attrs(web), attrs(py)
        assert set(wa) == set(pa), set(wa) ^ set(pa)
        for k in wa:
            assert same(wa[k], pa[k]), (k, wa[k], pa[k])

        assert list(web.variables) == list(py.variables)
        for name in web.variables:
            w, p = web[name], py[name]
            w.set_auto_maskandscale(False)
            p.set_auto_maskandscale(False)
            assert w.dimensions == p.dimensions and w.dtype == p.dtype, name
            va, vb = attrs(w), attrs(p)
            assert set(va) == set(vb), (name, set(va) ^ set(vb))
            for k in va:
                assert same(va[k], vb[k]), (name, k, va[k], vb[k])
            np.testing.assert_allclose(w[:], p[:], rtol=0, atol=1e-12, err_msg=name)


def test_values_and_metadata():
    with Dataset(FIXTURES / "netcdf" / "header.nc") as ds:
        assert ds.Conventions == "CF-1.8, ACDD-1.3"
        assert ds.processing_rows_trimmed_leading == 2
        depth, corrected = ds["depth"][:], ds["depth_corrected"][:]
        np.testing.assert_allclose(corrected - depth, 0.02, atol=1e-12)
        np.testing.assert_allclose(ds["mudline_elevation"][:], 1.25 - corrected, atol=1e-12)
        assert ds["latitude"][:].mask.all()  # header.csv has no GPS fix
        echo = ds["echo_strength"][:]
        assert echo.shape == (12, 7) and echo.mask[0, 5]
