CNX Fentanyl Reproducible Analysis Pipeline
===========================================

This repository includes both:
- a legacy multi-step pipeline, and
- a new single-file pipeline that reproduces the paper outputs from one monthly input file.

Purpose
-------
Rebuild the monthly analysis data and reproduce the three key figures plus the
summary statistics table used in the paper.

Single-file reproduction (recommended)
--------------------------------------
Use:
- `repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R`

Starting data file (already included in repo):
- `repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv`
  - contains monthly shipments (`tx_raw`),
  - monthly fentanyl seizures (`seizure_lbs_raw`),
  - monthly overdose rolling-12 counts (`overdose_12m_rolling`).

Policy input (already included in repo):
- `repro_pipeline/data/raw/policy_table_updated_all.csv`

RStudio quick start
-------------------
1) Open the project folder in RStudio (set working directory to repo root).
2) Run:
   `source("repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R")`
3) Outputs are written automatically to:
   - figures: `repro_pipeline/output/figures`
   - tables: `repro_pipeline/output/tables`
   - analysis datasets: `repro_pipeline/data/processed`

Required raw inputs (source locations in this project)
------------------------------------------------------
For the single-file pipeline:
1) `repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv`
2) `repro_pipeline/data/raw/policy_table_updated_all.csv`

For the legacy multi-step pipeline:
1) `repro_pipeline/data/raw/overdoseDeathsData_cleaned.csv` (CDC-style 12m rolling overdose counts)
2) `overdose_raw.csv` (monthly overdose counts; generated from rolling counts or provided directly)
3) `Shipment Data/altana_cnx_transactions.csv` **NOTE: Proprietary Data - Aggregated monthly transactions are provided in monthly_input_with_rolling_overdose.csv**
4) `Drug Seizures/nationwide-drugs-fy19-fy22.csv`
5) `Drug Seizures/nationwide-drugs-fy23-fy26-dec.csv`
6) `tables/policy_table_updated_all.csv`

Pipeline scripts
----------------
00) `repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R` (primary script)
   - Reads one monthly input file containing shipments, fentanyl seizures, and overdose rolling-12 counts.
   - Recovers monthly overdose counts from the rolling-12 series.
   - Builds analysis data and first-difference variables.
   - Produces:
     - `plot_scaled_overlay_minimal_smooth_all_to_2025_06.png`
     - `plot_changepoints_shipments_only.png`
     - `plot_shipments_loess_policy_lines.png`
     - `summary_statistics_through_2025_06.csv`
   - Also writes analysis datasets:
     - `series_monthly_from_single_input.csv`
     - `overdose_monthly_from_rolling12.csv`
     - `shipments_monthly_from_single_input.csv`
     - `fentanyl_seizures_monthly_from_single_input.csv`
     - `overdose_rolling_reconstruction_diagnostics.csv`

0) `repro_pipeline/scripts/00_transform_overdose_rolling12_to_monthly.R` (optional pre-step)
   - Use this to transform the CDC rolling 12-month overdose count 
     series to a raw monthly count series.
   - Writes `overdose_raw.csv` with columns:
     - `date`, `variable`, `raw_count`

1) `repro_pipeline/scripts/01_build_monthly_series.R`
   - Reads raw overdose, shipment, and seizure files.
   - Copies raw input files into:
     `repro_pipeline/data/raw`
   - Cleans and aggregates each source to monthly series.
   - Writes cleaned datasets into:
     `repro_pipeline/data/processed`
   - Outputs:
     - overdose_monthly.csv
     - shipments_monthly.csv
     - fentanyl_seizures_monthly.csv
     - series_monthly_raw.csv
     - series_monthly_through_2025_06.csv
     - coverage_summary.csv

2) `repro_pipeline/scripts/02_make_figures_tables.R`
   - Uses processed monthly series + policy table to generate:
     - plot_scaled_overlay_minimal_smooth_all_to_2025_06.png
     - plot_changepoints_shipments_only.png
     - plot_shipments_loess_policy_lines.png
     - summary_statistics_through_2025_06.csv
   - Writes figures to:
     `repro_pipeline/output/figures`
   - Writes tables to:
     `repro_pipeline/output/tables`

Data construction details
-------------------------
The pipeline standardizes all source file column names to lowercase,
then builds one monthly series per domain (`overdose_raw`, `tx_raw`,
`seizure_lbs_raw`) keyed on `month` (first day of month).

Overdose data (CDC rolling-12-month source -> monthly raw series)
-----------------------------------------------------------------
- The main pipeline expects `overdose_raw.csv` with `date` + `raw_count`.
- If your source data are CDC trailing 12-month counts, run:
  `repro_pipeline/scripts/00_transform_overdose_rolling12_to_monthly.R`
  first.
- Transformation logic:
  - observed rolling series: `R_t = M_t + ... + M_(t-11)`
  - unknowns include observed months plus 11 latent pre-sample months
  - solve for monthly `M_t` using non-negative optimization with a smoothness
    penalty so the recovered monthly path is plausible and reproducible.
- Then `01_build_monthly_series.R`:
  - parses `date` to month start,
  - keeps synthetic-opioid overdose rows when `variable` is present,
  - sums to one value per month (`overdose_raw`).

Shipment data (Altana transactions -> monthly transaction counts)
-----------------------------------------------------------------
- Reads `Shipment Data/altana_cnx_transactions.csv` as character columns first
  to avoid accidental type coercion.
- Detects the transaction date field from:
  - `transaction_date`, `date`, or `tx_date`
- Parses mixed date-time formats (`ymd_hms`, `ymd`, `mdy`), floors to month,
  and drops unparseable dates.
- Aggregates monthly shipments as:
  - distinct `transaction_id` count if `transaction_id` exists,
  - otherwise simple row count.
- Completes the monthly sequence from min to max observed month and fills
  missing months with `0` shipments.

Fentanyl seizure data (CBP fiscal files -> calendar-month lbs)
--------------------------------------------------------------
- Combines the two CBP files:
  - `nationwide-drugs-fy19-fy22.csv`
  - `nationwide-drugs-fy23-fy26-dec.csv`
- Requires these harmonized fields: `fy`, `month_abbv`, `drug_type`,
  `sum_qty_lbs`.
- Converts fiscal-year month labels to calendar month:
  - if month is Oct-Dec (`month_num >= 10`), calendar year = `FY - 1`
  - else calendar year = `FY`
- Filters to `drug_type == "Fentanyl"`, converts pounds to numeric, then sums
  monthly total pounds (`seizure_lbs_raw`).
- Completes month gaps and fills missing months with `0` lbs.

Merged analysis series
----------------------
- `01_build_monthly_series.R` full-joins overdose, shipment, and seizure
  monthly series by `month`.
- Also computes first differences for each series:
  - `d_overdose`, `d_tx`, `d_seizure_lbs`
- Writes:
  - full span: `series_monthly_raw.csv`
  - restricted span through June 2025: `series_monthly_through_2025_06.csv`
  - coverage summary: `coverage_summary.csv`

How to run
----------
From project root:

1) Recommended single-file run:
   Rscript repro_pipeline/scripts/00_all_in_one_pipeline_from_monthly_start.R --input="repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv" --policy="repro_pipeline/data/raw/policy_table_updated_all.csv"
2) Optional legacy pre-step (only if starting from rolling 12-month overdose counts):
   Rscript repro_pipeline/scripts/00_transform_overdose_rolling12_to_monthly.R --input="repro_pipeline/data/raw/overdoseDeathsData_cleaned.csv" --output="overdose_raw.csv"
3) Legacy step: Rscript repro_pipeline/scripts/01_build_monthly_series.R
4) Legacy step: Rscript repro_pipeline/scripts/02_make_figures_tables.R

R package dependencies
----------------------
- dplyr
- readr
- tidyr
- stringr
- lubridate
- ggplot2
- changepoint
- scales

Raw and cleaned CSV availability
--------------------------------
- Raw copies for download:
  `repro_pipeline/data/raw`
- Cleaned/processed CSV for download:
  `repro_pipeline/data/processed`
- Final table CSV for download:
  `repro_pipeline/output/tables`
