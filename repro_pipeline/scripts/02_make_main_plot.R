#!/usr/bin/env Rscript

# ------------------------------------------------------------
# Replication Script 02 (Main Figure)
# Creates:
# - plot_scaled_overlay_minimal_smooth_all_to_2025_06.png
# ------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(lubridate)
  library(ggplot2)
  library(scales)
})

input_series_path <- "repro_pipeline/data/raw/monthly_input_with_rolling_overdose.csv"
input_overdose_path <- "repro_pipeline/data/raw/overdose_raw_from_rolling.csv"
fig_dir <- "repro_pipeline/output/figures"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# Read monthly input panel and transformed overdose series.
monthly_input <- readr::read_csv(input_series_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  dplyr::rename_with(~ gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(.x))))

overdose_monthly <- readr::read_csv(input_overdose_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  dplyr::rename_with(~ gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(.x)))) %>%
  mutate(month = as.Date(date), raw_count = as.numeric(raw_count)) %>%
  filter(!is.na(month), !is.na(raw_count)) %>%
  group_by(month) %>%
  summarise(overdose_raw = sum(raw_count, na.rm = TRUE), .groups = "drop")

series_monthly <- monthly_input %>%
  mutate(
    month = as.Date(month),
    tx_raw = as.numeric(tx_raw),
    seizure_lbs_raw = as.numeric(seizure_lbs_raw)
  ) %>%
  filter(!is.na(month)) %>%
  group_by(month) %>%
  summarise(
    tx_raw = if (all(is.na(tx_raw))) NA_real_ else sum(tx_raw, na.rm = TRUE),
    seizure_lbs_raw = if (all(is.na(seizure_lbs_raw))) NA_real_ else sum(seizure_lbs_raw, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(overdose_monthly, by = "month") %>%
  select(month, overdose_raw, tx_raw, seizure_lbs_raw) %>%
  arrange(month) %>%
  filter(month <= as.Date("2025-06-01"))

# Min-max scale each series to [0, 1] through 2025-06.
od_min <- min(series_monthly$overdose_raw, na.rm = TRUE)
od_rng <- max(series_monthly$overdose_raw, na.rm = TRUE) - od_min

tx_min <- min(series_monthly$tx_raw, na.rm = TRUE)
tx_rng <- max(series_monthly$tx_raw, na.rm = TRUE) - tx_min

sz_min <- min(series_monthly$seizure_lbs_raw, na.rm = TRUE)
sz_rng <- max(series_monthly$seizure_lbs_raw, na.rm = TRUE) - sz_min

scaled_long <- series_monthly %>%
  mutate(
    overdose_scaled = if (is.finite(od_rng) && od_rng > 0) (overdose_raw - od_min) / od_rng else NA_real_,
    tx_scaled = if (is.finite(tx_rng) && tx_rng > 0) (tx_raw - tx_min) / tx_rng else NA_real_,
    seizure_scaled = if (is.finite(sz_rng) && sz_rng > 0) (seizure_lbs_raw - sz_min) / sz_rng else NA_real_
  ) %>%
  pivot_longer(
    cols = c(overdose_scaled, tx_scaled, seizure_scaled),
    names_to = "series",
    values_to = "value"
  ) %>%
  mutate(
    series = recode(
      series,
      overdose_scaled = "Overdose deaths",
      tx_scaled = "Shipments",
      seizure_scaled = "Fentanyl seizures"
    )
  )

# Marker positions on smoothed series
seizure_for_marker <- scaled_long %>%
  filter(series == "Fentanyl seizures", !is.na(value)) %>%
  arrange(month) %>%
  mutate(x_num = as.numeric(month))

marker_date <- as.Date("2023-05-01")
marker_y <- NA_real_
marker_date_raton <- as.Date("2023-01-05")
marker_y_raton <- NA_real_
marker_y_raton_plot <- NA_real_

if (nrow(seizure_for_marker) >= 4) {
  seizure_fit <- loess(
    value ~ x_num,
    data = seizure_for_marker,
    span = 0.075,
    control = loess.control(surface = "direct"),
    na.action = na.exclude
  )
  marker_y <- as.numeric(stats::predict(seizure_fit, newdata = data.frame(x_num = as.numeric(marker_date))))
  marker_y_raton <- as.numeric(stats::predict(seizure_fit, newdata = data.frame(x_num = as.numeric(marker_date_raton))))
  marker_y_raton_plot <- pmin(1, marker_y_raton + 0.055)
}

shipments_for_marker <- scaled_long %>%
  filter(series == "Shipments", !is.na(value)) %>%
  arrange(month) %>%
  mutate(x_num = as.numeric(month))

marker_date_china <- as.Date("2019-05-01")
marker_y_china <- NA_real_

if (nrow(shipments_for_marker) >= 4) {
  shipments_fit_marker <- loess(
    value ~ x_num,
    data = shipments_for_marker,
    span = 0.075,
    control = loess.control(surface = "direct"),
    na.action = na.exclude
  )
  marker_y_china <- as.numeric(stats::predict(shipments_fit_marker, newdata = data.frame(x_num = as.numeric(marker_date_china))))
}

# Main smoothed overlay figure.
plot_scaled_overlay <- ggplot() +
  geom_smooth(
    data = scaled_long,
    aes(x = month, y = value, color = series),
    method = "loess",
    formula = y ~ x,
    span = 0.075,
    se = FALSE,
    linewidth = 1.2,
    na.rm = TRUE
  ) +
  scale_color_manual(
    values = c(
      "Overdose deaths" = "#D55E00",
      "Shipments" = "#009E73",
      "Fentanyl seizures" = "#000000"
    ),
    name = NULL
  ) +
  scale_x_date(
    limits = c(as.Date("2018-06-01"), as.Date("2025-06-01")),
    date_breaks = "4 month",
    date_labels = "%b %Y",
    expand = expansion(mult = 0, add = 0)
  ) +
  scale_y_continuous(breaks = seq(0, 1, by = 0.1), labels = scales::number_format(accuracy = 0.1)) +
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
    geom_point(data = tibble::tibble(month = marker_date, value = marker_y), aes(x = month, y = value), inherit.aes = FALSE,
               size = 3.2, stroke = 1, color = "#000000", fill = "white", shape = 21, alpha = 0.95) +
    annotate("curve", x = as.Date("2023-11-15"), y = max(0.10, min(0.88, marker_y + 0.02)),
             xend = marker_date, yend = marker_y, curvature = -0.25,
             arrow = grid::arrow(length = grid::unit(0.16, "cm")), linewidth = 0.6, color = "#000000") +
    geom_label(data = tibble::tibble(x = as.Date("2023-10-01"), y = max(0.10, min(0.88, marker_y + 0.02)),
                                     label = "Los Chapitos Bans\nFentanyl Activities"),
               aes(x = x, y = y, label = label), inherit.aes = FALSE, hjust = 0, vjust = -0.4,
               size = 3.6, color = "#000000", fontface = "bold", fill = "white", linewidth = 0)
}

if (is.finite(marker_y_china)) {
  plot_scaled_overlay <- plot_scaled_overlay +
    geom_point(data = tibble::tibble(month = marker_date_china, value = marker_y_china), aes(x = month, y = value), inherit.aes = FALSE,
               size = 3.2, stroke = 1, color = "#009E73", fill = "white", shape = 21, alpha = 0.95) +
    annotate("curve", x = as.Date("2018-10-01"), y = max(0.18, min(0.92, marker_y_china + 0.24)),
             xend = marker_date_china, yend = marker_y_china, curvature = -0.20,
             arrow = grid::arrow(length = grid::unit(0.16, "cm")), linewidth = 0.6, color = "#009E73") +
    geom_label(data = tibble::tibble(x = as.Date("2018-08-01"), y = max(0.16, min(0.90, marker_y_china + 0.21)),
                                     label = "Broad Chinese Controls\non Fentanyl Precursors"),
               aes(x = x, y = y, label = label), inherit.aes = FALSE, hjust = 0, vjust = -0.4,
               size = 3.6, color = "#009E73", fontface = "bold", fill = "white", linewidth = 0)
}

if (is.finite(marker_y_raton)) {
  plot_scaled_overlay <- plot_scaled_overlay +
    geom_point(data = tibble::tibble(month = marker_date_raton, value = marker_y_raton_plot), aes(x = month, y = value), inherit.aes = FALSE,
               size = 3.2, stroke = 1, color = "#000000", fill = "white", shape = 21, alpha = 0.95) +
    annotate("curve", x = as.Date("2022-10-01"), y = 0.20,
             xend = marker_date_raton, yend = marker_y_raton_plot, curvature = 0.20,
             arrow = grid::arrow(length = grid::unit(0.16, "cm")), linewidth = 0.6, color = "#000000") +
    geom_label(data = tibble::tibble(x = as.Date("2022-08-10"), y = 0.12, label = "El Ratón Captured"),
               aes(x = x, y = y, label = label), inherit.aes = FALSE, hjust = 0, vjust = -0.4,
               size = 3.6, color = "#000000", fontface = "bold", fill = "white", linewidth = 0)
}

# Save main paper figure.
ggsave(
  filename = file.path(fig_dir, "plot_scaled_overlay_minimal_smooth_all_to_2025_06.png"),
  plot = plot_scaled_overlay,
  width = 12,
  height = 7,
  dpi = 300
)

#cat("Wrote:", file.path(fig_dir, "plot_scaled_overlay_minimal_smooth_all_to_2025_06.png"), "\n")
