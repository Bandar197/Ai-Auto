"""uds-scan only probes approved addresses (developer prompt rule 1.5): no blind 0x700-0x7EF sweep."""

from automind.cli import uds_profiles


def test_no_profile_is_a_blind_sweep():
    profiles = uds_profiles()
    assert "sweep11" not in profiles
    for name, cands in profiles.items():
        assert len(cands) < 24, name  # a blind band would be 240 addresses


def test_make_profiles_come_from_the_registry():
    p = uds_profiles()
    hy = p["hyundai"]
    assert any(req == 0x7D4 for _, req, *_ in hy)  # registry SRS candidate
    assert any(label.endswith("?") for label, *_ in hy)  # unverified addresses are marked
    assert p["kia"] == hy  # alias
    assert {"obd11", "fca", "generic"} <= set(p)
