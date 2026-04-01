CNX Fentanyl Reproducible Analysis Pipeline
===========================================

This repository includes a reproducible two-script R pipeline in:
- `repro_pipeline/scripts`

Purpose
-------
Rebuild the core aggregated monthly datasets and reproduce the three key figures plus the
summary statistics table used in the study.

Required raw inputs (source locations in this project)
------------------------------------------------------
1) `overdoseDeathsData_cleaned.csv` (CDC 12m rolling overdose counts for synthetic opioids)
2) `overdose_raw.csv` (monthly overdose counts; generated from item 1 by script 00, or provided directly)
3) `altana_cnx_transactions.csv` **NOTE: Proprietary Data - Aggregated monthly transactions are located in `shipments_monthly.csv`**
4) `nationwide-drugs-fy19-fy22.csv`
5) `nationwide-drugs-fy23-fy26-dec.csv`
6) `policy_table_updated_all.csv`

Pipeline scripts
----------------
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

1) Optional (only if starting from rolling 12-month overdose counts):
   Rscript repro_pipeline/scripts/00_transform_overdose_rolling12_to_monthly.R --input="repro_pipeline/data/raw/overdoseDeathsData_cleaned.csv" --output="overdose_raw.csv"
2) Rscript repro_pipeline/scripts/01_build_monthly_series.R
3) Rscript repro_pipeline/scripts/02_make_figures_tables.R

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
