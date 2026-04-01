"Cartel Decapitation Disrupts Fentanyl Supply Chains" Data and Analysis Pipeline
================================================================================

This is the primary, single-file reproducible workflow used to generate the analysis
data, figures, and table contained in the paper.

Use this script:
- `repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R`

Starting input files (included in repo)
---------------------------------------
1) `repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv`
   - `month`
   - `tx_raw` (monthly shipments)
   - `seizure_lbs_raw` (monthly fentanyl seizures, lbs)
   - `overdose_12m_rolling` (monthly trailing-12 overdose counts)
2) `repro_pipeline/data/raw/policy_table_updated_all.csv`

What this script does
---------------------
1) Reads one monthly file containing shipments, seizures, and rolling-12 overdoses.
2) Recovers monthly overdose counts from the rolling-12 overdose series.
3) Builds analysis series and first differences.
4) Produces the paper outputs:
   - `repro_pipeline/output/figures/plot_scaled_overlay_minimal_smooth_all_to_2025_06.png`
   - `repro_pipeline/output/figures/plot_changepoints_shipments_only.png`
   - `repro_pipeline/output/figures/plot_shipments_loess_policy_lines.png`
   - `repro_pipeline/output/tables/summary_statistics_through_2025_06.csv`
5) Writes analysis data:
   - `repro_pipeline/data/processed/series_monthly_from_single_input.csv`
   - `repro_pipeline/data/processed/overdose_monthly_from_rolling12.csv`
   - `repro_pipeline/data/processed/shipments_monthly_from_single_input.csv`
   - `repro_pipeline/data/processed/fentanyl_seizures_monthly_from_single_input.csv`
   - `repro_pipeline/output/tables/overdose_rolling_reconstruction_diagnostics.csv`

RStudio quick start
-------------------
Open the repo in RStudio and run:

`source("repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R")`

CLI run
-------
From repo root:

`Rscript repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R --input="repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv" --policy="repro_pipeline/data/raw/policy_table_updated_all.csv" --end_date="2025-06-30" --window=12 --lambda=25 --smooth_span=0.075`

Packages needed
---------------
- dplyr
- readr
- tidyr
- stringr
- lubridate
- ggplot2
- changepoint
- scales
