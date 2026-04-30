cnx-fentanyl-repro-pipeline
===========================

This repository contains a minimal replication workflow for the paper outputs.

Included files
--------------

Data (required inputs):
- `repro_pipeline/data/raw/overdoseDeathsData_cleaned.csv`
- `repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv`
- `repro_pipeline/data/raw/policy_table_updated_all.csv`

Scripts:
- `repro_pipeline/scripts/01_transform_overdose_rolling12_to_monthly.R`
- `repro_pipeline/scripts/02_make_main_plot.R`
- `repro_pipeline/scripts/03_make_supplemental_outputs.R`

Outputs:
- `repro_pipeline/output/figures/plot_scaled_overlay_minimal_smooth_all_to_2025_06.png`
- `repro_pipeline/output/figures/plot_shipments_loess_policy_lines.png`
- `repro_pipeline/output/figures/plot_seizures_loess_event_lines.png`
- `repro_pipeline/output/tables/summary_statistics_through_2025_06.csv`

How to run
----------

From the repository root:

1. `Rscript repro_pipeline/scripts/01_transform_overdose_rolling12_to_monthly.R`
2. `Rscript repro_pipeline/scripts/02_make_main_plot.R`
3. `Rscript repro_pipeline/scripts/03_make_supplemental_outputs.R`

Script details
--------------

1) `01_transform_overdose_rolling12_to_monthly.R`
- Reads CDC rolling 12-month overdose counts.
- Reconstructs monthly counts via constrained deconvolution.
- Writes `repro_pipeline/data/raw/overdose_raw_from_rolling.csv`.

2) `02_make_main_plot.R`
- Reads monthly overdoses, shipments, and seizures.
- Produces the main scaled LOESS figure.

3) `03_make_supplemental_outputs.R`
- Produces shipment-policy overlay plot.
- Produces seizure-cartel-event overlay plot.
- Produces summary statistics table through 2025-06.

R packages
----------
- dplyr
- readr
- tidyr
- lubridate
- stringr
- ggplot2
- scales
