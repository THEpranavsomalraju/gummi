# Gummi: limits, sources, and what is draft

Status: DRAFT. Every accuracy number in these reports is a draft until Pranav and Nikhil approve it for judges.
Quote numbers with "draft" until then.

## What Gummi is, in one paragraph

Gummi is a CGM coach for adults with prediabetes or type 2 diabetes who do not take insulin. It predicts where
glucose heads after meals, nudges a walk before a predicted spike, and grades every prediction against what
happened. Dexcom's API delivers data one hour late, so Gummi estimates that hour for coaching only. It never shows
the estimate as a current reading and never gives treatment, medication or insulin advice. Current readings come
from the Dexcom app.

## Limits to say out loud

- 15 BIG IDEAs participants (one of the 16 was excluded for missing data: 75% completeness and a 21.9-hour gap,
  matching the published exclusion). All are adults with normal to prediabetic HbA1c (5.3 to 6.4%), about 9 days
  each. Nothing is shown beyond this cohort.
- Food logs are self-reported. They contain errors: one meal logs 463 g of carbs, and two rows logged fat equal to
  their calories (repaired from the calories).
- Meal times are as logged.
- The cohort is flat, so forecasts at long horizons drift toward the person's mean.
- Gummi predicts the peaks of big spikes too low: by about 11 mg/dL on average and about 31 mg/dL after the sugary
  standardized breakfast, after the October 3 big-meal fix. Before the fix these were 14 and 40 (spike_fix.md).
- The walk effect comes from the literature, not from this data: Buffey et al. 2022, Sports Medicine, light walking
  breaks versus sitting, d = -0.72. BIG IDEAs has no walk labels.
- The IMU50 check validates only the walking-intensity bands against wrist data and ActiGraph METs. It says nothing
  about glucose.
- Evaluation is always participant-grouped. No person is ever in both training and testing, and replayed
  participants are predicted by a fold model that never saw them ("out-of-sample").

## Baselines that sit next to every number

- CGM-only: the published linear method on the last 24 readings. Its 30-minute RMSE of 13.90 mg/dL (Seyedebrahimi
  et al. 2026) is reproduced exactly.
- Last value: repeating the last confirmed reading.

## Sources

- BIG IDEAs Lab Glycemic Variability and Wearable Device Data v1.1.3, PhysioNet; Bent B, et al. npj Digital Medicine
  2021;4:89. Open Data Commons Attribution License v1.0.
- Seyedebrahimi, Ojeda, Zarrintaj (2026). A Leakage-Controlled Evaluation of Multimodal Sensor Fusion for
  Wrist-Worn Glucose Estimation. medRxiv, doi:10.64898/2026.08.03.26359550.
- Buffey AJ, Herring MP, Langley CK, Donnelly AE, Carson BP. Sports Medicine 2022;52(8):1765-1787.
  doi:10.1007/s40279-022-01649-4.
- IMU50, Zenodo record 21468410, CC BY 4.0.
- Tudor-Locke C, et al. Int J Behav Nutr Phys Act 2019;16:8. doi:10.1186/s12966-019-0769-6 (cadence bands).
