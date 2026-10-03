"""IMU50 (Zenodo 10.5281/zenodo.21468410, CC BY 4.0): a small check of Gummi's cadence bands on wrist data (D-19).

Reads a few subjects straight out of the 46.7 GB IMU50.zip with HTTP range requests; nothing close to the full
archive is downloaded (hard stop over 5 GB).
"""
from .cadence import CADENCE_BANDS, band_of, hourly_check, minute_features
from .remote import HttpRangeFile, open_subject, subject_minutes

__all__ = ["CADENCE_BANDS", "band_of", "hourly_check", "minute_features", "HttpRangeFile", "open_subject",
           "subject_minutes"]
