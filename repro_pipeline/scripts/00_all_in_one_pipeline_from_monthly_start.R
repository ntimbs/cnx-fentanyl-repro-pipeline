#!/usr/bin/env Rscript

# -------------------------------------------------------------------
# SIMPLE ONE-FILE PIPELINE
# -------------------------------------------------------------------
# What this script does:
# 1) Reads the two required input files.
# 2) Converts rolling 12-month overdose counts to monthly counts.
# 3) Scales overdose, shipments, and seizures to 0-1.
# 4) Produces 3 figures + 1 summary table used in the paper.
#
# NOTE:
# - This script assumes your working directory is the repo root.
# - No helper functions are used so the workflow is easy to follow.
# -------------------------------------------------------------------

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

# -----------------------------
# 0) File paths and parameters
# -----------------------------

input_path <- "repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv"
policy_path <- "repro_pipeline/data/raw/policy_table_updated_all.csv"

processed_dir <- "repro_pipeline/data/processed"
figure_dir <- "repro_pipeline/output/figures"
table_dir <- "repro_pipeline/output/tables"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

end_month <- as.Date("2025-06-01")
axis_end_month <- as.Date("2025-07-01")
smooth_span <- 0.075

# ---------------------------------
# 1) Read inputs and standardize
# ---------------------------------

if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path)
}

if (!file.exists(policy_path)) {
  stop("Policy file not found: ", policy_path)
}

series_input <- readr::read_csv(input_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  dplyr::rename_with(~ gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(.x))))

policy_input <- readr::read_csv(policy_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  dplyr::rename_with(~ gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(.x))))

required_cols <- c("month", "tx_raw", "seizure_lbs_raw", "overdose_12m_rolling")
missing_required <- setdiff(required_cols, names(series_input))
if (length(missing_required) > 0) {
  stop("Missing required columns in input file: ", paste(missing_required, collapse = ", "))
}

series_monthly <- series_input %>%
  mutate(
    month = as.Date(month),
    tx_raw = as.numeric(tx_raw),
    seizure_lbs_raw = as.numeric(seizure_lbs_raw),
    overdose_12m_rolling = as.numeric(overdose_12m_rolling)
  ) %>%
  filter(!is.na(month)) %>%
  group_by(month) %>%
  summarise(
    tx_raw = if (all(is.na(tx_raw))) NA_real_ else sum(tx_raw, na.rm = TRUE),
    seizure_lbs_raw = if (all(is.na(seizure_lbs_raw))) NA_real_ else sum(seizure_lbs_raw, na.rm = TRUE),
    overdose_12m_rolling = if (all(is.na(overdose_12m_rolling))) NA_real_ else sum(overdose_12m_rolling, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(month)

if (any(is.na(series_monthly$overdose_12m_rolling))) {
  stop("overdose_12m_rolling has missing values. Fill/remove those months before running this script.")
}

# ------------------------------------------------------------
# 2) Convert rolling 12-month overdoses to monthly overdoses
# ------------------------------------------------------------
# Simple equation:
#   monthly_t = (rolling_t - rolling_{t-1}) + monthly_{t-12}
#
# Initialization choice used here:
# - First 12 months are set to rolling_12m / 12.
# - Negative recovered values are set to 0.

r <- series_monthly$overdose_12m_rolling
n <- length(r)
m <- rep(NA_real_, n)

if (n >= 1) {
  m[1:min(12, n)] <- r[1:min(12, n)] / 12
}
if (n >= 13) {
  for (i in 13:n) {
    m[i] <- (r[i] - r[i - 1]) + m[i - 12]
  }
}

series_monthly$overdose_raw <- pmax(m, 0)

series_monthly <- series_monthly %>%
  select(month, overdose_raw, tx_raw, seizure_lbs_raw, overdose_12m_rolling)

series_to_end <- series_monthly %>%
  filter(month <= end_month)

if (nrow(series_to_end) == 0) {
  stop("No observations at or before ", end_month)
}

# Write processed analysis data
readr::write_csv(series_monthly, file.path(processed_dir, "series_monthly_from_single_input.csv"))
readr::write_csv(series_monthly %>% select(month, overdose_raw), file.path(processed_dir, "overdose_monthly_from_rolling12.csv"))
readr::write_csv(series_monthly %>% select(month, tx_raw), file.path(processed_dir, "shipments_monthly_from_single_input.csv"))
readr::write_csv(series_monthly %>% select(month, seizure_lbs_raw), file.path(processed_dir, "fentanyl_seizures_monthly_from_single_input.csv"))

# -----------------------------------------
# 3) Scale all three series to [0, 1]
# -----------------------------------------

od_min <- min(series_to_end$overdose_raw, na.rm = TRUE)
od_max <- max(series_to_end$overdose_raw, na.rm = TRUE)
od_rng <- od_max - od_min

tx_min <- min(series_to_end$tx_raw, na.rm = TRUE)
tx_max <- max(series_to_end$tx_raw, na.rm = TRUE)
tx_rng <- tx_max - tx_min

sz_min <- min(series_to_end$seizure_lbs_raw, na.rm = TRUE)
sz_max <- max(series_to_end$seizure_lbs_raw, na.rm = TRUE)
sz_rng <- sz_max - sz_min

series_scaled <- series_to_end %>%
  mutate(
    overdose_scaled = if (is.finite(od_rng) && od_rng > 0) (overdose_raw - od_min) / od_rng else NA_real_,
    tx_scaled = if (is.finite(tx_rng) && tx_rng > 0) (tx_raw - tx_min) / tx_rng else NA_real_,
    seizure_scaled = if (is.finite(sz_rng) && sz_rng > 0) (seizure_lbs_raw - sz_min) / sz_rng else NA_real_
  )

scaled_long <- series_scaled %>%
  select(month, overdose_scaled, tx_scaled, seizure_scaled) %>%
  pivot_longer(cols = -month, names_to = "series", values_to = "value") %>%
  mutate(
    series = recode(
      series,
      overdose_scaled = "Overdose deaths",
      tx_scaled = "Shipments",
      seizure_scaled = "Fentanyl seizures"
    )
  )

# -----------------------------------------
# 4) Figure 1: main overlay plot
# -----------------------------------------

# Smooth seizure line separately so the May-2023 marker can sit on the smoothed curve.
seizure_for_marker <- scaled_long %>%
  filter(series == "Fentanyl seizures", !is.na(value)) %>%
  arrange(month) %>%
  mutate(x_num = as.numeric(month))

marker_date <- as.Date("2023-05-01")
marker_y <- NA_real_

if (nrow(seizure_for_marker) >= 4) {
  seizure_fit <- loess(
    value ~ x_num,
    data = seizure_for_marker,
    span = smooth_span,
    control = loess.control(surface = "direct"),
    na.action = na.exclude
  )
  marker_y <- as.numeric(stats::predict(seizure_fit, newdata = data.frame(x_num = as.numeric(marker_date))))
}

context_start <- as.Date("2022-08-01")
context_end <- as.Date("2023-01-05")

color_vals <- c(
  "Overdose deaths" = "#E57200",
  "Shipments" = "#5E6B7A",
  "Fentanyl seizures" = "#232D4B"
)

plot_scaled_overlay <- ggplot() +
  geom_rect(
    aes(xmin = context_start, xmax = context_end, ymin = -Inf, ymax = Inf),
    fill = "#DCEAF8",
    alpha = 0.50,
    inherit.aes = FALSE
  ) +
  geom_vline(xintercept = context_start, linetype = "dotted", linewidth = 0.35, color = "#6C7A89", alpha = 0.9) +
  geom_vline(xintercept = context_end, linetype = "dotted", linewidth = 0.35, color = "#6C7A89", alpha = 0.9) +
  geom_smooth(
    data = scaled_long,
    aes(x = month, y = value, color = series),
    method = "loess",
    span = smooth_span,
    se = FALSE,
    linewidth = 1.0,
    na.rm = TRUE
  ) +
  geom_label(
    data = tibble::tibble(
      x = as.Date("2022-10-18"),
      y = 1.03,
      label = "Joint U.S.-Mexico Operation"
    ),
    aes(x = x, y = y, label = label),
    inherit.aes = FALSE,
    fontface = "bold",
    size = 4.2,
    fill = "white",
    linewidth = 0
  ) +
  scale_color_manual(values = color_vals, name = NULL) +
  scale_x_date(
    limits = c(as.Date("2018-06-01"), as.Date("2025-06-01")),
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
    legend.title = element_blank(),
    legend.text = element_text(size = 12),
    plot.margin = margin(t = 22, r = 10, b = 10, l = 10)
  )

if (is.finite(marker_y)) {
  plot_scaled_overlay <- plot_scaled_overlay +
    geom_point(
      data = tibble::tibble(month = marker_date, value = marker_y),
      aes(x = month, y = value),
      inherit.aes = FALSE,
      size = 3.2,
      stroke = 1,
      color = "#232D4B",
      fill = "white",
      shape = 21,
      alpha = 0.95
    ) +
    annotate(
      "curve",
      x = as.Date("2023-11-15"),
      y = max(0.10, min(0.88, marker_y + 0.02)),
      xend = marker_date,
      yend = marker_y,
      curvature = -0.25,
      arrow = grid::arrow(length = grid::unit(0.16, "cm")),
      linewidth = 0.6,
      color = "#232D4B"
    ) +
    geom_label(
      data = tibble::tibble(
        x = as.Date("2023-10-01"),
        y = max(0.10, min(0.88, marker_y + 0.02)),
        label = "Los Chapitos Bans\nFentanyl Activities"
      ),
      aes(x = x, y = y, label = label),
      inherit.aes = FALSE,
      hjust = 0,
      vjust = -0.4,
      size = 3.6,
      color = "#232D4B",
      fontface = "bold",
      fill = "white",
      linewidth = 0
    )
}

# -----------------------------------------
# 5) Figure 2: shipments + changepoints
# -----------------------------------------

shipments_monthly <- series_monthly %>%
  select(month, shipments = tx_raw) %>%
  filter(!is.na(shipments), month <= end_month) %>%
  arrange(month) %>%
  mutate(x_num = as.numeric(month))

shipments_fit <- loess(
  shipments ~ x_num,
  data = shipments_monthly,
  span = smooth_span,
  control = loess.control(surface = "direct"),
  na.action = na.exclude
)

shipments_monthly <- shipments_monthly %>%
  mutate(shipments_smooth = as.numeric(stats::predict(shipments_fit, newdata = data.frame(x_num = x_num))))

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
  filter(!is.na(shipments_smooth))

plot_changepoints_shipments_only <- ggplot(shipments_monthly, aes(x = month, y = shipments_smooth)) +
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
    size = 2.0
  ) +
  scale_x_date(
    limits = c(min(shipments_monthly$month, na.rm = TRUE), axis_end_month),
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

# -----------------------------------------
# 6) Figure 3: shipments + policy lines
# -----------------------------------------

policy_dates <- tibble::tibble(policy_month = as.Date(character()))

if (all(c("month_year", "jurisdiction") %in% names(policy_input))) {
  policy_dates <- policy_input %>%
    mutate(
      policy_month_a = suppressWarnings(lubridate::ymd(paste0(month_year, "-01"), quiet = TRUE)),
      policy_month_b = suppressWarnings(lubridate::ymd(month_year, quiet = TRUE)),
      policy_month_c = suppressWarnings(lubridate::ym(month_year, quiet = TRUE)),
      policy_month = dplyr::coalesce(policy_month_a, policy_month_b, policy_month_c),
      jurisdiction_std = case_when(
        jurisdiction %in% c("US", "USA") ~ "US",
        jurisdiction == "Mexico" ~ "Mexico",
        jurisdiction == "China" ~ "China",
        jurisdiction %in% c("UN", "United Nations") ~ "UN",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(policy_month), !is.na(jurisdiction_std)) %>%
    filter(policy_month >= min(shipments_monthly$month, na.rm = TRUE), policy_month <= end_month) %>%
    distinct(policy_month) %>%
    arrange(policy_month)
}

plot_shipments_loess_policy_lines <- ggplot(shipments_monthly, aes(x = month, y = shipments_smooth)) +
  geom_line(linewidth = 1.1, color = "#2c3e50", na.rm = TRUE) +
  geom_vline(
    data = policy_dates,
    aes(xintercept = policy_month),
    linetype = "dashed",
    linewidth = 0.45,
    color = "black",
    alpha = 0.85
  ) +
  scale_x_date(
    limits = c(min(shipments_monthly$month, na.rm = TRUE), axis_end_month),
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

# -----------------------------------------
# 7) Table: summary statistics
# -----------------------------------------

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
common_data <- series_to_end %>% filter(month >= common_start, month <= common_end)

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

# -----------------------------------------
# 8) Write figures and table
# -----------------------------------------

ggsave(
  filename = file.path(figure_dir, "plot_scaled_overlay_minimal_smooth_all_to_2025_06.png"),
  plot = plot_scaled_overlay,
  width = 12,
  height = 7,
  dpi = 300
)

ggsave(
  filename = file.path(figure_dir, "plot_changepoints_shipments_only.png"),
  plot = plot_changepoints_shipments_only,
  width = 12,
  height = 6,
  dpi = 300
)

ggsave(
  filename = file.path(figure_dir, "plot_shipments_loess_policy_lines.png"),
  plot = plot_shipments_loess_policy_lines,
  width = 12,
  height = 6,
  dpi = 300
)

readr::write_csv(summary_stats, file.path(table_dir, "summary_statistics_through_2025_06.csv"))

message("Done.")
message("Created/updated:")
message("- repro_pipeline/data/processed/series_monthly_from_single_input.csv")
message("- repro_pipeline/data/processed/overdose_monthly_from_rolling12.csv")
message("- repro_pipeline/data/processed/shipments_monthly_from_single_input.csv")
message("- repro_pipeline/data/processed/fentanyl_seizures_monthly_from_single_input.csv")
message("- repro_pipeline/output/figures/plot_scaled_overlay_minimal_smooth_all_to_2025_06.png")
message("- repro_pipeline/output/figures/plot_changepoints_shipments_only.png")
message("- repro_pipeline/output/figures/plot_shipments_loess_policy_lines.png")
message("- repro_pipeline/output/tables/summary_statistics_through_2025_06.csv")
