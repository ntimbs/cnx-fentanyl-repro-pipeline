cnx-fentanyl-repro-pipeline
===========================

This repository contains two workflows:

1) `repro_pipeline/replication_minimal/` (recommended for sharing/replication)
2) `repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R` (legacy all-in-one workflow)

Recommended Replication Workflow
--------------------------------

Use the files under:

- `repro_pipeline/replication_minimal/`

### Minimal input files

- `repro_pipeline/replication_minimal/data/overdoseDeathsData_cleaned.csv`
  - CDC synthetic opioid overdose series in rolling 12-month form.
- `repro_pipeline/replication_minimal/data/monthly_input_with_rolling_overdose.csv`
  - Monthly shipments (`tx_raw`) and fentanyl seizures (`seizure_lbs_raw`), plus rolling overdose field.
- `repro_pipeline/replication_minimal/data/policy_table_updated_all.csv`
  - Policy month-year table used for shipment-policy overlays.

### Scripts

1) `repro_pipeline/replication_minimal/scripts/01_transform_overdose_rolling12_to_monthly.R`
   - Reconstructs monthly overdose counts from rolling 12-month CDC counts.
   - Writes: `repro_pipeline/replication_minimal/data/overdose_raw_from_rolling.csv`

2) `repro_pipeline/replication_minimal/scripts/02_make_main_plot.R`
   - Creates main paper figure:
   - `repro_pipeline/replication_minimal/output/figures/plot_scaled_overlay_minimal_smooth_all_to_2025_06.png`

3) `repro_pipeline/replication_minimal/scripts/03_make_supplemental_outputs.R`
   - Creates supplemental outputs:
   - `repro_pipeline/replication_minimal/output/figures/plot_shipments_loess_policy_lines.png`
   - `repro_pipeline/replication_minimal/output/figures/plot_seizures_loess_event_lines.png`
   - `repro_pipeline/replication_minimal/output/tables/summary_statistics_through_2025_06.csv`

### Run order

From the repo root:

1) `Rscript repro_pipeline/replication_minimal/scripts/01_transform_overdose_rolling12_to_monthly.R`
2) `Rscript repro_pipeline/replication_minimal/scripts/02_make_main_plot.R`
3) `Rscript repro_pipeline/replication_minimal/scripts/03_make_supplemental_outputs.R`

Legacy All-in-One Workflow
--------------------------

- `repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R`

This script is retained for continuity with earlier project versions. It reads raw inputs from `repro_pipeline/data/raw/` and writes processed data/figures/tables to `repro_pipeline/data/processed/` and `repro_pipeline/output/`.

R Packages
----------

- dplyr
- readr
- tidyr
- lubridate
- stringr
- ggplot2
- scales
- changepoint
