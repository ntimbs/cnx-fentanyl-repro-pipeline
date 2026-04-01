CNX Fentanyl Reproducible Analysis Pipeline
===========================================

This repository includes a reproducible two-script R pipeline in:
- `repro_pipeline/scripts`

Goal
----
Rebuild the core monthly datasets and reproduce the three key figures plus the
summary statistics table used in the study.

Required raw inputs (source locations in this project)
------------------------------------------------------
1) `overdose_raw.csv`
2) `Shipment Data/altana_cnx_transactions.csv`
3) `Drug Seizures/nationwide-drugs-fy19-fy22.csv`
4) `Drug Seizures/nationwide-drugs-fy23-fy26-dec.csv`
5) `tables/policy_table_updated_all.csv`

Pipeline scripts
----------------
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

How to run
----------
From project root:

1) Rscript repro_pipeline/scripts/01_build_monthly_series.R
2) Rscript repro_pipeline/scripts/02_make_figures_tables.R

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

GitHub note for large file
--------------------------
The shipment raw file (altana_cnx_transactions.csv) is large (~635 MB). Standard
GitHub may require Git LFS for this file if you plan to push the raw copy.
