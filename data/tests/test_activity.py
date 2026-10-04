import pytest

from gummi_activity import intensity_from_cadence, summarize_walk


@pytest.mark.parametrize("spm,label", [(0, "sedentary"), (None, "sedentary"), (60, "light"), (99.9, "light"),
                                       (100, "moderate"), (129, "moderate"), (130, "vigorous"), (150, "vigorous")])
def test_bands(spm, label):
    assert intensity_from_cadence(spm)["intensity"] == label


def test_mets_only_where_published():
    assert intensity_from_cadence(90)["mets_estimate"] is None
    assert intensity_from_cadence(100)["mets_estimate"] == 3.0
    assert intensity_from_cadence(130)["mets_estimate"] == 6.0


def test_summarize_walk_eleven_minutes():
    samples = [{"value": 107, "start": f"2026-10-04T12:{m:02d}:00Z", "end": f"2026-10-04T12:{m + 1:02d}:00Z"}
               for m in range(0, 11)]
    w = summarize_walk(samples, walk_effect={"forecast_peak_drop_mg_dl": 9.5, "effect_source": "literature"})
    assert w["minutes"] == 11 and w["steps"] == 1177 and w["cadence_spm"] == 107
    assert w["intensity"] == "moderate"
    assert w["forecast_peak_drop_mg_dl"] == 9.5 and w["effect_source"] == "literature"


def test_summarize_walk_clips_to_window():
    samples = [{"value": 600, "start": "2026-10-04T12:00:00Z", "end": "2026-10-04T12:10:00Z"}]
    w = summarize_walk(samples, started_at="2026-10-04T12:05:00Z", ended_at="2026-10-04T12:10:00Z")
    assert w["steps"] == 300 and w["minutes"] == 5 and w["cadence_spm"] == 60
