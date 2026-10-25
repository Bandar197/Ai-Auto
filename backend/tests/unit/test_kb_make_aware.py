"""Manufacturer-specific codes are only described for the right make; VIN → make via WMI."""

from automind.diagnosis.kb import KnowledgeBase, get_kb, is_manufacturer_specific, make_from_vin


def test_manufacturer_ranges():
    for c in ["P1326", "P3001", "B1620", "B2000", "C1201", "U1000"]:
        assert is_manufacturer_specific(c), c
    for c in ["P0106", "P2101", "P3400", "B0001", "C0035", "U0100", "U3000"]:
        assert not is_manufacturer_specific(c), c


def test_oem_entry_only_for_its_make():
    kb = KnowledgeBase(
        {"codes": {"P0106": {"en": "MAP"}}},
        {"profiles": [{"make": "hyundai", "aliases": ["kia"], "source": "licensed file",
                       "codes": {"P1326": {"en": "Knock Sensor Detection System"}}}]},
    )
    assert kb.lookup("P1326", make="hyundai")["oem_make"] == "hyundai"
    assert kb.lookup("P1326", make="kia")["en"] == "Knock Sensor Detection System"
    assert kb.lookup("P1326", make="toyota") is None  # never borrowed from another make
    assert kb.lookup("P1326") is None
    assert kb.lookup("P0106", make="toyota")["en"] == "MAP"  # generic still works


def test_shipped_kb_has_no_guessed_oem_codes():
    kb = get_kb()
    assert kb.lookup("P1326", make="hyundai") is None
    assert kb.structure("B1620") == {"system": "body", "is_generic": False}


def test_make_from_vin():
    assert make_from_vin("KMHEC41CBCA123456") == "hyundai"
    assert make_from_vin("JTHBK1GG2E2123456") == "lexus"  # longest prefix wins over JT
    assert make_from_vin("JTDBR32E720123456") == "toyota"
    assert make_from_vin("ZZZ00000000000000") is None
    assert make_from_vin("KMH") is None
    assert make_from_vin("KMHEC41CBCA12345O") is None  # O is not a valid VIN character


def test_shipped_community_overlay():
    kb = get_kb()
    ford = kb.lookup("P1000", make="ford")
    assert ford and ford["oem_verified"] is False and "dtc-database" in ford["oem_source"]
    assert kb.lookup("P1100", make="toyota")["en"] == "BARO Sensor Circuit"
    assert kb.lookup("P1100", make="infiniti") is None  # known-bad source file was excluded
    assert kb.lookup("P1000", make="toyota") is None or kb.lookup("P1000", make="toyota")["oem_make"] == "toyota"
