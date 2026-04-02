"Cartel Decapitation Disrupts Fentanyl Supply Chains" Data and Analysis Pipeline
================================================================================

This is the primary, single-file reproducible workflow used to generate the analysis
data, figures, and table contained in the paper.

Use this script:
- `repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R`

Input Files (included in repo)
------------------------------
1) `repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv`
   - Purpose: core monthly input used for analysis and plotting.
   - Required columns:
     - `month`: month-year date (first of month preferred).
     - `tx_raw`: monthly count of precursor shipment transactions.
     - `seizure_lbs_raw`: monthly fentanyl seizures in pounds.
     - `overdose_12m_rolling`: monthly trailing 12-month overdose count.
2) `repro_pipeline/data/raw/policy_table_updated_all.csv`
   - Purpose: policy event dates used for shipment-policy overlay figure.
   - Expected fields used by script:
     - `month_year` (or date-equivalent month field),
     - `jurisdiction` (`US`, `Mexico`, `China`, `UN`).

What this script does
---------------------
1) Reads one monthly file containing shipments, seizures, and rolling-12 overdoses.
2) Recovers monthly overdose counts from the rolling-12 overdose series.
3) Builds analysis series.
4) Writes processed analysis datasets.
5) Produces final figures and summary table used in the paper.

Output Files: Processed Analysis Data
-------------------------------------
1) `repro_pipeline/data/processed/series_monthly_from_single_input.csv`
   - Master monthly analysis file.
   - Contains: `month`, recovered monthly overdoses (`overdose_raw`), shipments (`tx_raw`), seizures (`seizure_lbs_raw`), and original rolling overdose input (`overdose_rolling_12m`).
2) `repro_pipeline/data/processed/overdose_monthly_from_rolling12.csv`
   - Recovered monthly overdose series only (`month`, `overdose_raw`).
3) `repro_pipeline/data/processed/shipments_monthly_from_single_input.csv`
   - Monthly shipment series only (`month`, `tx_raw`).
4) `repro_pipeline/data/processed/fentanyl_seizures_monthly_from_single_input.csv`
   - Monthly fentanyl seizure series only (`month`, `seizure_lbs_raw`).

Output Figures
--------------
1) `repro_pipeline/output/figures/plot_scaled_overlay_minimal_smooth_all_to_2025_06.png`
   - Main overlay figure with overdoses, shipments, and seizures scaled to 0-1.
   - Uses LOESS smoothing (`smooth_span` argument; default `0.075`).
   - Includes contextual annotation for the operation window and May 2023 seizure-line marker.
2) `repro_pipeline/output/figures/plot_changepoints_shipments_only.png`
   - Shipment-only trend with LOESS smoothed line.
   - Red dashed lines indicate significant PELT/MBIC changepoints (`minseglen = 6`).
3) `repro_pipeline/output/figures/plot_shipments_loess_policy_lines.png`
   - Shipment trend with black dashed policy implementation lines overlaid.
   - Policy lines filtered to date range and jurisdictions of interest.

Output Table
------------
1) `repro_pipeline/output/tables/summary_statistics_through_2025_06.csv`
   - Summary statistics through June 2025 for each series:
     - coverage start/end month,
     - months covered,
     - total counts/quantity,
     - common overlap window and totals.

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
