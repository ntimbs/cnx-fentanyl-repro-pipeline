#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(lubridate)
  library(stringr)
  library(ggplot2)
  library(changepoint)
  library(scales)
})

# ---------------------------------------------------------------------------
# Single-file pipeline
# - Input: ONE monthly file with shipments, fentanyl seizures, and 12m rolling overdose counts
# - Transform: recover monthly overdose counts from rolling-12 series
# - Output: 3 figures + 1 table used in paper
# ---------------------------------------------------------------------------

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

get_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_flag <- "--file="
  hit <- args[startsWith(args, file_flag)]
  if (length(hit) == 0) return(NA_character_)
  normalizePath(sub(file_flag, "", hit[[1]]), mustWork = FALSE)
}

find_root_dir <- function(script_path = NA_character_) {
  if (!is.na(script_path)) {
    return(normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE))
  }

  cwd <- normalizePath(getwd(), mustWork = TRUE)
  candidates <- c(
    cwd,
    dirname(cwd),
    dirname(dirname(cwd)),
    dirname(dirname(dirname(cwd)))
  )
  candidates <- unique(candidates)
  hit <- candidates[file.exists(file.path(candidates, "repro_pipeline"))][1]
  if (is.na(hit)) return(cwd)
  normalizePath(hit, mustWork = TRUE)
}

parse_arg <- function(name, default = NULL) {
  key <- paste0("--", name, "=")
  hit <- commandArgs(trailingOnly = TRUE)
  hit <- hit[startsWith(hit, key)]
  if (length(hit) == 0) return(default)
  sub(key, "", hit[[1]])
}

standardize_names <- function(df) {
  nm <- names(df)
  nm <- tolower(nm)
  nm <- gsub("[^a-z0-9]+", "_", nm)
  nm <- gsub("^_|_$", "", nm)
  names(df) <- nm
  df
}

parse_month_date <- function(x) {
  out <- suppressWarnings(as.Date(x))
  na_idx <- is.na(out)
  if (any(na_idx)) out[na_idx] <- suppressWarnings(ymd(x[na_idx], quiet = TRUE))
  na_idx <- is.na(out)
  if (any(na_idx)) out[na_idx] <- suppressWarnings(mdy(x[na_idx], quiet = TRUE))
  na_idx <- is.na(out)
  if (any(na_idx)) out[na_idx] <- suppressWarnings(as.Date(paste0(x[na_idx], "-01")))
  floor_date(out, unit = "month")
}

find_col <- function(df, candidates, arg_value = NULL) {
  if (!is.null(arg_value) && nzchar(arg_value) && arg_value %in% names(df)) return(arg_value)
  hit <- candidates[candidates %in% names(df)][1]
  if (is.na(hit)) NA_character_ else hit
}

minmax_scale <- function(x) {
  rng <- max(x, na.rm = TRUE) - min(x, na.rm = TRUE)
  if (!is.finite(rng) || rng == 0) rep(NA_real_, length(x)) else (x - min(x, na.rm = TRUE)) / rng
}

build_rolling_design <- function(n_obs, window = 12L) {
  n_unknown <- n_obs + window - 1L
  A <- matrix(0, nrow = n_obs, ncol = n_unknown)
  for (t in seq_len(n_obs)) {
    A[t, t:(t + window - 1L)] <- 1
  }
  A
}

build_second_difference <- function(n_unknown) {
  if (n_unknown < 3L) return(matrix(0, nrow = 0, ncol = n_unknown))
  D <- matrix(0, nrow = n_unknown - 2L, ncol = n_unknown)
  for (i in seq_len(n_unknown - 2L)) {
    D[i, i] <- 1
    D[i, i + 1L] <- -2
    D[i, i + 2L] <- 1
  }
  D
}

recover_monthly_from_rolling <- function(rolling_counts, window = 12L, lambda = 25, maxit = 20000L) {
  rolling_counts <- as.numeric(rolling_counts)
  n_obs <- length(rolling_counts)
  A <- build_rolling_design(n_obs, window = window)
  n_unknown <- ncol(A)
  D <- build_second_difference(n_unknown)

  objective <- function(m) {
    err <- as.vector(A %*% m - rolling_counts)
    smooth <- if (nrow(D) > 0) as.vector(D %*% m) else numeric(0)
    sum(err * err) + lambda * sum(smooth * smooth)
  }

  gradient <- function(m) {
    g <- 2 * as.vector(crossprod(A, A %*% m - rolling_counts))
    if (nrow(D) > 0) {
      g <- g + 2 * lambda * as.vector(crossprod(D, D %*% m))
    }
    g
  }

  m0 <- rep(mean(rolling_counts, na.rm = TRUE) / window, n_unknown)
  fit <- optim(
    par = m0,
    fn = objective,
    gr = gradient,
    method = "L-BFGS-B",
    lower = rep(0, n_unknown),
    control = list(maxit = maxit)
  )

  if (!identical(fit$convergence, 0L)) {
    warning("Rolling-to-monthly optimization did not fully converge (code ", fit$convergence, ").")
  }

  latent <- fit$par
  monthly <- latent[window:n_unknown]
  list(monthly = monthly, convergence = fit$convergence, objective = fit$value)
}

# ---------------------------------------------------------------------------
# Paths + options
# ---------------------------------------------------------------------------

script_path <- get_script_path()
ROOT_DIR <- find_root_dir(script_path)

PIPE_DIR <- file.path(ROOT_DIR, "repro_pipeline")
RAW_DIR <- file.path(PIPE_DIR, "data", "raw")
PROCESSED_DIR <- file.path(PIPE_DIR, "data", "processed")
OUTPUT_DIR <- file.path(PIPE_DIR, "output")
FIGURE_DIR <- file.path(OUTPUT_DIR, "figures")
TABLE_DIR <- file.path(OUTPUT_DIR, "tables")
dir.create(PROCESSED_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGURE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)

START_FILE <- parse_arg(
  "input",
  default = file.path(RAW_DIR, "monthly_input_with_rolling_overdose.csv")
)
POLICY_FILE <- parse_arg(
  "policy",
  default = file.path(RAW_DIR, "policy_table_updated_all.csv")
)
END_DATE <- as.Date(parse_arg("end_date", default = "2025-06-30"))
END_MONTH <- floor_date(END_DATE, unit = "month")
AXIS_END_MONTH <- ceiling_date(END_DATE, unit = "month")
WINDOW <- as.integer(parse_arg("window", default = "12"))
LAMBDA <- as.numeric(parse_arg("lambda", default = "25"))
SMOOTH_SPAN <- as.numeric(parse_arg("smooth_span", default = "0.075"))

if (!file.exists(START_FILE)) {
  stop(
    "Missing input monthly file: ", START_FILE, "\n",
    "Expected a single file with month + shipments + fentanyl seizures + overdose rolling-12 counts.\n",
    "Pass a custom path with --input=/path/to/file.csv"
  )
}

if (is.na(WINDOW) || WINDOW < 2L) stop("--window must be an integer >= 2")
if (is.na(LAMBDA) || LAMBDA < 0) stop("--lambda must be non-negative")
if (is.na(SMOOTH_SPAN) || SMOOTH_SPAN <= 0 || SMOOTH_SPAN > 1) stop("--smooth_span must be in (0, 1]")

# ---------------------------------------------------------------------------
# 1) Read one monthly input file and build analysis series
# ---------------------------------------------------------------------------

starter <- readr::read_csv(START_FILE, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  standardize_names()

month_col <- find_col(starter, c("month", "date", "month_year"), parse_arg("month_col", default = NULL))
tx_col <- find_col(starter, c("tx_raw", "shipments", "shipment_count", "transactions", "monthly_transactions", "n_transactions"), parse_arg("tx_col", default = NULL))
seizure_col <- find_col(starter, c("seizure_lbs_raw", "seizure_lbs", "fentanyl_seizures_lbs", "qty_lbs", "seizures"), parse_arg("seizure_col", default = NULL))
rolling_col <- find_col(starter, c("overdose_12m_rolling", "overdose_rolling_12m", "rolling_12m_overdose", "count", "rolling_count", "overdose_12m"), parse_arg("rolling_col", default = NULL))

missing_needed <- c(
  if (is.na(month_col)) "month/date column",
  if (is.na(tx_col)) "shipments column",
  if (is.na(seizure_col)) "fentanyl seizures column",
  if (is.na(rolling_col)) "overdose rolling-12 column"
)
if (length(missing_needed) > 0) {
  stop(
    "Input file is missing required fields:\n- ",
    paste(missing_needed, collapse = "\n- "),
    "\nUse --month_col=, --tx_col=, --seizure_col=, --rolling_col= to override auto-detection."
  )
}

series_input <- starter %>%
  mutate(
    month = parse_month_date(.data[[month_col]]),
    tx_raw = as.numeric(.data[[tx_col]]),
    seizure_lbs_raw = as.numeric(.data[[seizure_col]]),
    overdose_rolling_12m = as.numeric(.data[[rolling_col]])
  ) %>%
  filter(!is.na(month)) %>%
  group_by(month) %>%
  summarise(
    tx_raw = if (all(is.na(tx_raw))) NA_real_ else sum(tx_raw, na.rm = TRUE),
    seizure_lbs_raw = if (all(is.na(seizure_lbs_raw))) NA_real_ else sum(seizure_lbs_raw, na.rm = TRUE),
    overdose_rolling_12m = if (all(is.na(overdose_rolling_12m))) NA_real_ else sum(overdose_rolling_12m, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(month)

if (any(is.na(series_input$overdose_rolling_12m))) {
  missing_n <- sum(is.na(series_input$overdose_rolling_12m))
  stop(
    "Input contains ", missing_n, " month(s) with missing rolling overdose counts. ",
    "Provide a complete rolling-12 series (or filter to complete months) before inversion."
  )
}

if (nrow(series_input) < WINDOW) {
  stop("Need at least ", WINDOW, " monthly observations to recover monthly overdose counts from rolling data.")
}

overdose_fit <- recover_monthly_from_rolling(
  rolling_counts = series_input$overdose_rolling_12m,
  window = WINDOW,
  lambda = LAMBDA
)

series_monthly <- series_input %>%
  mutate(
    overdose_raw = as.integer(round(overdose_fit$monthly)),
    d_overdose = overdose_raw - dplyr::lag(overdose_raw),
    d_tx = tx_raw - dplyr::lag(tx_raw),
    d_seizure_lbs = seizure_lbs_raw - dplyr::lag(seizure_lbs_raw)
  ) %>%
  select(month, overdose_raw, tx_raw, seizure_lbs_raw, overdose_rolling_12m, d_overdose, d_tx, d_seizure_lbs)

series_to_end <- series_monthly %>%
  filter(month <= END_MONTH)

if (nrow(series_to_end) == 0) {
  stop("No data at or before end_date = ", END_DATE)
}

reconstructed_roll <- as.numeric(stats::filter(series_monthly$overdose_raw, rep(1, WINDOW), sides = 1))
rolling_diagnostics <- series_monthly %>%
  transmute(
    month,
    overdose_rolling_12m_observed = overdose_rolling_12m,
    overdose_rolling_12m_reconstructed = reconstructed_roll,
    abs_error = abs(overdose_rolling_12m_observed - overdose_rolling_12m_reconstructed)
  )

readr::write_csv(series_monthly, file.path(PROCESSED_DIR, "series_monthly_from_single_input.csv"))
readr::write_csv(
  series_monthly %>% select(month, overdose_raw),
  file.path(PROCESSED_DIR, "overdose_monthly_from_rolling12.csv")
)
readr::write_csv(
  series_monthly %>% select(month, tx_raw),
  file.path(PROCESSED_DIR, "shipments_monthly_from_single_input.csv")
)
readr::write_csv(
  series_monthly %>% select(month, seizure_lbs_raw),
  file.path(PROCESSED_DIR, "fentanyl_seizures_monthly_from_single_input.csv")
)
readr::write_csv(rolling_diagnostics, file.path(TABLE_DIR, "overdose_rolling_reconstruction_diagnostics.csv"))

# ---------------------------------------------------------------------------
# 2) Figure: scaled overlay (minimal smoothing)
# ---------------------------------------------------------------------------

scaled_long <- series_to_end %>%
  mutate(
    across(
      c(overdose_raw, tx_raw, seizure_lbs_raw),
      minmax_scale,
      .names = "{.col}_norm"
    )
  ) %>%
  select(month, overdose_raw_norm, tx_raw_norm, seizure_lbs_raw_norm) %>%
  pivot_longer(cols = -month, names_to = "series", values_to = "value") %>%
  mutate(
    series = recode(
      series,
      overdose_raw_norm = "Overdose deaths",
      tx_raw_norm = "Shipments",
      seizure_lbs_raw_norm = "Fentanyl seizures (lbs)"
    )
  )

scaled_long_smooth <- scaled_long %>%
  filter(!is.na(value)) %>%
  group_by(series) %>%
  arrange(month, .by_group = TRUE) %>%
  group_modify(~ {
    df <- .x %>% transmute(month, value, x_num = as.numeric(month))
    if (nrow(df) < 4) return(tibble::tibble(month = df$month, value_smooth = NA_real_))
    fit <- loess(
      value ~ x_num,
      data = df,
      span = SMOOTH_SPAN,
      control = loess.control(surface = "direct"),
      na.action = na.exclude
    )
    tibble::tibble(
      month = df$month,
      value_smooth = as.numeric(predict(fit, newdata = data.frame(x_num = df$x_num)))
    )
  }) %>%
  ungroup()

plot_x_start <- as.Date("2018-06-01")
plot_x_end <- as.Date("2025-06-01")

context_windows <- tibble::tribble(
  ~period, ~xmin, ~xmax, ~fill_col,
  "Operation Mongoose Azteca", as.Date("2022-08-01"), as.Date("2023-01-05"), "#DCEAF8"
) %>%
  mutate(
    xmin = pmax(xmin, plot_x_start),
    xmax = pmin(xmax, plot_x_end)
  ) %>%
  filter(xmax > xmin)

context_annotation <- context_windows %>%
  transmute(
    x = xmin + floor(as.numeric(xmax - xmin) / 2),
    y = 1.03,
    label = "Joint U.S.-Mexico Operation"
  )

seizure_marker <- scaled_long_smooth %>%
  filter(series == "Fentanyl seizures (lbs)", month == as.Date("2023-05-01"), !is.na(value_smooth)) %>%
  transmute(month, value = value_smooth) %>%
  slice(1)

seizure_annotation <- tibble::tibble(
  x = as.Date(character()),
  x_arrow = as.Date(character()),
  y = numeric(),
  xend = as.Date(character()),
  yend = numeric(),
  label = character()
)

if (nrow(seizure_marker) > 0) {
  label_x <- as.Date("2023-10-01")
  if (label_x < plot_x_start) label_x <- plot_x_start + days(1)
  if (label_x > plot_x_end) label_x <- plot_x_end - days(1)
  label_x_arrow <- label_x + days(45)
  if (label_x_arrow > plot_x_end) label_x_arrow <- plot_x_end - days(1)
  label_y <- max(0.10, min(0.88, seizure_marker$value[[1]] + 0.02))
  seizure_annotation <- tibble::tibble(
    x = label_x,
    x_arrow = label_x_arrow,
    y = label_y,
    xend = seizure_marker$month[[1]],
    yend = seizure_marker$value[[1]],
    label = "Los Chapitos Bans\nFentanyl Activities"
  )
}

color_vals <- c(
  "Overdose deaths" = "#E57200",
  "Shipments" = "#5E6B7A",
  "Fentanyl seizures (lbs)" = "#232D4B"
)

plot_scaled_overlay_minimal_smooth_all_to_2025_06 <- ggplot() +
  geom_rect(
    data = context_windows,
    aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
    inherit.aes = FALSE,
    fill = context_windows$fill_col,
    alpha = 0.50,
    show.legend = FALSE
  ) +
  geom_vline(
    data = context_windows,
    aes(xintercept = xmin),
    linetype = "dotted",
    linewidth = 0.35,
    color = "#6C7A89",
    alpha = 0.9,
    show.legend = FALSE
  ) +
  geom_vline(
    data = context_windows,
    aes(xintercept = xmax),
    linetype = "dotted",
    linewidth = 0.35,
    color = "#6C7A89",
    alpha = 0.9,
    show.legend = FALSE
  ) +
  geom_line(
    data = scaled_long_smooth,
    aes(x = month, y = value_smooth, color = series),
    linewidth = 1.0,
    na.rm = TRUE
  ) +
  geom_point(
    data = seizure_marker,
    aes(x = month, y = value),
    inherit.aes = FALSE,
    size = 3.2,
    stroke = 1,
    color = "#232D4B",
    fill = "white",
    shape = 21,
    alpha = 0.95
  ) +
  geom_curve(
    data = seizure_annotation,
    aes(x = x_arrow, y = y, xend = xend, yend = yend),
    inherit.aes = FALSE,
    curvature = -0.25,
    arrow = grid::arrow(length = grid::unit(0.16, "cm")),
    linewidth = 0.6,
    color = "#232D4B"
  ) +
  geom_label(
    data = context_annotation,
    aes(x = x, y = y, label = label),
    inherit.aes = FALSE,
    fontface = "bold",
    size = 4.2,
    color = "#1f1f1f",
    fill = "white",
    linewidth = 0,
    label.padding = grid::unit(0.18, "lines")
  ) +
  geom_label(
    data = seizure_annotation,
    aes(x = x, y = y, label = label),
    inherit.aes = FALSE,
    hjust = 0,
    vjust = -0.4,
    size = 3.6,
    color = "#232D4B",
    fontface = "bold",
    fill = "white",
    linewidth = 0,
    label.padding = grid::unit(0.18, "lines")
  ) +
  scale_color_manual(
    values = color_vals,
    breaks = c("Overdose deaths", "Shipments", "Fentanyl seizures (lbs)"),
    labels = c("Overdose deaths", "Shipments", "Fentanyl seizures"),
    drop = TRUE,
    name = NULL
  ) +
  guides(color = guide_legend(order = 1, nrow = 1, byrow = TRUE), fill = "none") +
  scale_x_date(
    limits = c(plot_x_start, plot_x_end),
    date_breaks = "4 month",
    date_labels = "%b %Y",
    expand = expansion(mult = 0, add = 0)
  ) +
  scale_y_continuous(
    breaks = seq(0, 1, by = 0.1),
    labels = scales::number_format(accuracy = 0.1)
  ) +
  coord_cartesian(ylim = c(0, 1), clip = "off") +
  labs(
    title = "Fentanyl Precursor Shipments, Seizures, and Overdose Deaths",
    subtitle = NULL,
    x = "Month",
    y = "Scaled value"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(size = 20, face = "bold"),
    axis.title = element_text(size = 15, face = "bold"),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1, size = 12),
    axis.text.y = element_text(size = 12),
    legend.position = "bottom",
    legend.direction = "horizontal",
    legend.box = "vertical",
    legend.title = element_blank(),
    legend.key.width = grid::unit(1.2, "lines"),
    legend.key.height = grid::unit(0.8, "lines"),
    legend.text = element_text(size = 12),
    legend.spacing.x = grid::unit(0.2, "cm"),
    plot.margin = margin(t = 22, r = 10, b = 10, l = 10)
  )

# ---------------------------------------------------------------------------
# 3) Figure: shipments-only changepoint
# ---------------------------------------------------------------------------

shipments_monthly <- series_monthly %>%
  select(month, shipments = tx_raw) %>%
  filter(!is.na(shipments), month <= END_MONTH) %>%
  arrange(month)

shipments_smooth <- shipments_monthly %>%
  mutate(x_num = as.numeric(month))

shipments_loess_fit <- loess(
  shipments ~ x_num,
  data = shipments_smooth,
  span = SMOOTH_SPAN,
  control = loess.control(surface = "direct"),
  na.action = na.exclude
)

shipments_smooth <- shipments_smooth %>%
  mutate(shipments_smooth = as.numeric(predict(shipments_loess_fit, newdata = data.frame(x_num = x_num))))

cp_fit <- changepoint::cpt.meanvar(
  shipments_monthly$shipments,
  method = "PELT",
  penalty = "MBIC",
  minseglen = 6L,
  class = TRUE
)

cp_idx <- changepoint::cpts(cp_fit)
cp_idx <- cp_idx[cp_idx > 0 & cp_idx < nrow(shipments_monthly)]

cp_points <- shipments_monthly %>%
  slice(cp_idx) %>%
  mutate(
    x_num = as.numeric(month),
    shipments_smooth = as.numeric(predict(shipments_loess_fit, newdata = data.frame(x_num = x_num)))
  ) %>%
  filter(!is.na(shipments_smooth))

ship_axis_start <- min(shipments_monthly$month, na.rm = TRUE)
ship_axis_end <- AXIS_END_MONTH

plot_changepoints_shipments_only <- ggplot(shipments_smooth, aes(x = month, y = shipments_smooth)) +
  geom_line(linewidth = 1.0, color = "#2c3e50", alpha = 0.95, na.rm = TRUE) +
  geom_vline(
    data = cp_points,
    aes(xintercept = month),
    linetype = "dashed",
    linewidth = 0.8,
    color = "#d62728",
    alpha = 0.95
  ) +
  geom_point(
    data = cp_points,
    aes(x = month, y = shipments_smooth),
    color = "#d62728",
    size = 2.0,
    inherit.aes = FALSE
  ) +
  scale_x_date(
    limits = c(ship_axis_start, ship_axis_end),
    date_breaks = "6 month",
    date_labels = "%b %Y",
    expand = expansion(mult = 0, add = 0)
  ) +
  labs(
    title = "Change-Point Analysis: Shipments",
    subtitle = "Red lines indicate significant change-points",
    x = "Month",
    y = "Shipments"
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# ---------------------------------------------------------------------------
# 4) Figure: shipments with policy implementation lines
# ---------------------------------------------------------------------------

policy_dates <- tibble::tibble(policy_month = as.Date(character()))
if (file.exists(POLICY_FILE)) {
  policy_raw <- readr::read_csv(POLICY_FILE, show_col_types = FALSE, name_repair = "unique_quiet") %>%
    standardize_names()

  month_year_col <- find_col(policy_raw, c("month_year", "date", "month"), parse_arg("policy_month_col", default = NULL))
  jurisdiction_col <- find_col(policy_raw, c("jurisdiction", "entity"), parse_arg("policy_jurisdiction_col", default = NULL))

  if (!is.na(month_year_col) && !is.na(jurisdiction_col)) {
    policy_dates <- policy_raw %>%
      mutate(
        policy_month = as.Date(paste0(.data[[month_year_col]], "-01")),
        jurisdiction_std = case_when(
          .data[[jurisdiction_col]] %in% c("US", "USA") ~ "US",
          .data[[jurisdiction_col]] == "Mexico" ~ "Mexico",
          .data[[jurisdiction_col]] == "China" ~ "China",
          .data[[jurisdiction_col]] %in% c("UN", "United Nations") ~ "UN",
          TRUE ~ NA_character_
        )
      ) %>%
      filter(!is.na(jurisdiction_std), !is.na(policy_month)) %>%
      filter(policy_month >= ship_axis_start, policy_month <= END_MONTH) %>%
      distinct(policy_month) %>%
      arrange(policy_month)
  }
}

plot_shipments_loess_policy_lines <- ggplot(shipments_smooth, aes(x = month, y = shipments_smooth)) +
  geom_line(linewidth = 1.1, color = "#2c3e50", na.rm = TRUE) +
  geom_vline(
    data = policy_dates,
    aes(xintercept = policy_month),
    linetype = "dashed",
    linewidth = 0.45,
    color = "black",
    alpha = 0.85,
    show.legend = FALSE
  ) +
  scale_x_date(
    limits = c(ship_axis_start, ship_axis_end),
    date_breaks = "6 month",
    date_labels = "%b %Y",
    expand = expansion(mult = 0, add = 0)
  ) +
  labs(
    title = "Fentanyl precursor shipments and the policies that regulate them",
    subtitle = "Black lines indicate policy implementation dates",
    x = "Month",
    y = "Shipments"
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# ---------------------------------------------------------------------------
# 5) Table: summary statistics through June 2025
# ---------------------------------------------------------------------------

summary_stats <- tibble::tibble(
  series = c("Overdose deaths", "Shipments", "Fentanyl seized (lbs)"),
  start_month = c(
    min(series_to_end$month[!is.na(series_to_end$overdose_raw)]),
    min(series_to_end$month[!is.na(series_to_end$tx_raw)]),
    min(series_to_end$month[!is.na(series_to_end$seizure_lbs_raw)])
  ),
  end_month = c(
    max(series_to_end$month[!is.na(series_to_end$overdose_raw)]),
    max(series_to_end$month[!is.na(series_to_end$tx_raw)]),
    max(series_to_end$month[!is.na(series_to_end$seizure_lbs_raw)])
  ),
  months_covered = c(
    sum(!is.na(series_to_end$overdose_raw)),
    sum(!is.na(series_to_end$tx_raw)),
    sum(!is.na(series_to_end$seizure_lbs_raw))
  ),
  total_n = c(
    sum(series_to_end$overdose_raw, na.rm = TRUE),
    sum(series_to_end$tx_raw, na.rm = TRUE),
    sum(series_to_end$seizure_lbs_raw, na.rm = TRUE)
  )
)

common_start <- max(summary_stats$start_month)
common_end <- min(summary_stats$end_month)
common_data <- series_to_end %>%
  filter(month >= common_start, month <= common_end)

summary_stats <- summary_stats %>%
  mutate(
    common_window_start = common_start,
    common_window_end = common_end,
    common_months = nrow(common_data),
    common_total_n = c(
      sum(common_data$overdose_raw, na.rm = TRUE),
      sum(common_data$tx_raw, na.rm = TRUE),
      sum(common_data$seizure_lbs_raw, na.rm = TRUE)
    )
  )

# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------

ggsave(
  filename = file.path(FIGURE_DIR, "plot_scaled_overlay_minimal_smooth_all_to_2025_06.png"),
  plot = plot_scaled_overlay_minimal_smooth_all_to_2025_06,
  width = 12,
  height = 7,
  dpi = 300
)

ggsave(
  filename = file.path(FIGURE_DIR, "plot_changepoints_shipments_only.png"),
  plot = plot_changepoints_shipments_only,
  width = 12,
  height = 6,
  dpi = 300
)

ggsave(
  filename = file.path(FIGURE_DIR, "plot_shipments_loess_policy_lines.png"),
  plot = plot_shipments_loess_policy_lines,
  width = 12,
  height = 6,
  dpi = 300
)

readr::write_csv(summary_stats, file.path(TABLE_DIR, "summary_statistics_through_2025_06.csv"))

message("Single-file pipeline complete.")
message("Input file: ", START_FILE)
message("Recovered monthly overdose counts from rolling window = ", WINDOW, ", lambda = ", LAMBDA)
message("Optimization convergence code: ", overdose_fit$convergence)
message("Processed outputs written to: ", PROCESSED_DIR)
message("Figure outputs written to: ", FIGURE_DIR)
message("Table outputs written to: ", TABLE_DIR)
message("Files created:")
message("- series_monthly_from_single_input.csv")
message("- overdose_monthly_from_rolling12.csv")
message("- shipments_monthly_from_single_input.csv")
message("- fentanyl_seizures_monthly_from_single_input.csv")
message("- overdose_rolling_reconstruction_diagnostics.csv")
message("- plot_scaled_overlay_minimal_smooth_all_to_2025_06.png")
message("- plot_changepoints_shipments_only.png")
message("- plot_shipments_loess_policy_lines.png")
message("- summary_statistics_through_2025_06.csv")
