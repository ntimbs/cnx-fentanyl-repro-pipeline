#!/usr/bin/env Rscript

# ------------------------------------------------------------
# Replication Script 01
# Transform CDC 12-month rolling overdose counts to monthly counts
# ------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(stringr)
})

input_path <- "repro_pipeline/data/raw/overdoseDeathsData_cleaned.csv"
output_path <- "repro_pipeline/data/raw/overdose_raw_from_rolling.csv"

# 12-month rolling window and smoothness penalty for deconvolution.
window <- 12L
lambda <- 25

# Read and standardize column names.
raw_overdose <- readr::read_csv(input_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  dplyr::rename_with(~ gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(.x))))

rolling_monthly <- raw_overdose %>%
  mutate(
    month = floor_date(as.Date(date), unit = "month"),
    variable_std = if ("variable" %in% names(.)) str_to_lower(str_squish(variable)) else "synthetic opioid overdose deaths",
    rolling_12m = as.numeric(count)
  ) %>%
  filter(!is.na(month), !is.na(rolling_12m)) %>%
  filter(variable_std == "synthetic opioid overdose deaths") %>%
  group_by(month) %>%
  summarise(rolling_12m = sum(rolling_12m, na.rm = TRUE), .groups = "drop") %>%
  arrange(month)

# A * m = rolling_12m, where m is the latent monthly series.
n_obs <- nrow(rolling_monthly)
n_unknown <- n_obs + window - 1L
A <- matrix(0, nrow = n_obs, ncol = n_unknown)
for (t in seq_len(n_obs)) {
  A[t, t:(t + window - 1L)] <- 1
}

# Smoothness penalty on second differences of m.
D <- matrix(0, nrow = max(0, n_unknown - 2L), ncol = n_unknown)
if (n_unknown >= 3L) {
  for (i in seq_len(n_unknown - 2L)) {
    D[i, i] <- 1
    D[i, i + 1L] <- -2
    D[i, i + 2L] <- 1
  }
}

objective <- function(m) {
  fit_error <- as.vector(A %*% m - rolling_monthly$rolling_12m)
  smooth_error <- if (nrow(D) > 0) as.vector(D %*% m) else numeric(0)
  sum(fit_error * fit_error) + lambda * sum(smooth_error * smooth_error)
}

gradient <- function(m) {
  g <- 2 * as.vector(crossprod(A, A %*% m - rolling_monthly$rolling_12m))
  if (nrow(D) > 0) {
    g <- g + 2 * lambda * as.vector(crossprod(D, D %*% m))
  }
  g
}

start_vals <- rep(mean(rolling_monthly$rolling_12m, na.rm = TRUE) / window, n_unknown)
fit <- optim(
  par = start_vals,
  fn = objective,
  gr = gradient,
  method = "L-BFGS-B",
  lower = rep(0, n_unknown),
  control = list(maxit = 20000)
)

# Keep non-negative integer monthly estimates.
monthly_recovered <- pmax(0, as.integer(round(fit$par[window:n_unknown])))

overdose_monthly <- tibble::tibble(
  date = rolling_monthly$month,
  variable = "Synthetic opioid overdose deaths",
  raw_count = monthly_recovered
)

readr::write_csv(overdose_monthly, output_path)

#cat("Wrote:", output_path, "\n")
