"""API tests: every test starts from a clean database (reference data kept)."""

from __future__ import annotations

import pytest


def pytest_configure(config):
    config.addinivalue_line("markers", "nodb: pure test that needs no database")


@pytest.fixture(autouse=True)
def _clean(request):
    # Pure unit tests in this folder (e.g. the control policy) don't need a database.
    if request.node.get_closest_marker("nodb") is None:
        request.getfixturevalue("clean_db")
    yield
