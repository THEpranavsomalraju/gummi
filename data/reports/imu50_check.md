# IMU50 check: do Gummi's cadence bands track wrist activity? (D-19)

DRAFT, Data Lead. Not judge-facing until Nikhil approves the numbers (hard stop).

## Question

Gummi labels a walk light, moderate or vigorous from step cadence (gummi_activity: 1 to 99, 100 to 129, 130 or more
steps per minute; Tudor-Locke et al. 2019, D-44). BIG IDEAs has no activity labels, so IMU50 is used for one small,
honest check: in hours where the wrist shows more moderate-or-faster walking minutes, does the ActiGraph's own energy
estimate (hourly METs) go up?

## Data and method

- IMU50, Zenodo record 21468410 (CC BY 4.0): 50 healthy volunteers, ActiGraph wrist IMU at 128 Hz, hourly METs and
  calories from ActiGraph scoring. No glucose, no activity labels.
- 5 subjects (00, 05, 13, 20, 44), first 24 hours each. They are read straight out of the 46.7 GB zip with HTTP range
  requests: about 175 MB per subject and 885 MB in total, never the full archive (data/imu50/remote.py).
- Per minute: the dominant periodicity of the wrist acceleration between 0.6 and 3.5 Hz becomes a cadence
  estimate (arm swing at half the step rate is doubled). A minute counts as walking-like when that peak holds enough
  of the signal's power. This is a heuristic, not a step counter (D-47).
- Per hour: minutes in each Gummi band, joined to the ActiGraph METs for that hour. Only full hours count (50 or
  more minutes), which leaves 119 hours.
- Code: data/imu50/, data/scripts/run_imu50_check.py (local) and data/notebooks/04_imu50_cadence_check.py
  (Databricks job gummi_imu50_check). Tables: workspace.gummi_data.imu50_minutes and imu50_hourly_check.

## Result

| Moderate-or-faster minutes in the hour | Hours | Mean METs |
|---|---|---|
| 0 | 29 | 1.14 |
| 1 to 9 | 71 | 1.82 |
| 10 or more | 19 | 2.42 |

- Spearman correlation between moderate-or-faster minutes and METs: 0.74 over the 119 hours. Within each person it
  is 0.93 (00), 0.92 (05), 0.57 (13), 0.44 (20) and 0.89 (44), so the link holds inside each person, not only between
  people.
- Walking-like minutes by band: 342 light, 444 moderate, 102 vigorous.

## What it supports, and what it does not

Supported: hours with more minutes in Gummi's moderate-or-faster bands carry clearly higher energy expenditure on an
independent device's scoring, in all 5 people.

Not shown:
- That the per-minute cadence numbers are exact. There is no step-count ground truth, and the cadence comes from a
  wrist heuristic, while the app uses the phone's step counts.
- That walking lowers glucose. IMU50 has no glucose; that effect comes from the literature (D-11).

Pitch wording, if Nikhil approves: "We checked Gummi's walking-intensity bands against 119 hours of wrist data from
5 IMU50 volunteers: more moderate-or-faster minutes went with higher measured METs (Spearman 0.74)."

## Citation

- IMU50 dataset, Zenodo record 21468410, https://zenodo.org/records/21468410, CC BY 4.0.
- Cadence bands: Tudor-Locke C, Aguiar EJ, Han H, et al. Walking cadence (steps/min) and intensity in 21-40 year
  olds: CADENCE-adults. Int J Behav Nutr Phys Act. 2019;16:8. doi:10.1186/s12966-019-0769-6
