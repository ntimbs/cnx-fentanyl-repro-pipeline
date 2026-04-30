#!/usr/bin/env Rscript

# ------------------------------------------------------------
# Replication Script 03 (Supplemental Outputs)
# Creates:
# - plot_shipments_loess_policy_lines.png
# - plot_seizures_loess_event_lines.png
# - summary_statistics_through_2025_06.csv
# ------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(ggplot2)
})

input_series_path <- "repro_pipeline/replication_minimal/data/monthly_input_with_rolling_overdose.csv"
input_overdose_path <- "repro_pipeline/replication_minimal/data/overdose_raw_from_rolling.csv"
input_policy_path <- "repro_pipeline/replication_minimal/data/policy_table_updated_all.csv"

fig_dir <- "repro_pipeline/replication_minimal/output/figures"
tab_dir <- "repro_pipeline/replication_minimal/output/tables"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

# Read monthly input panel, policy table, and transformed overdose series.
monthly_input <- readr::read_csv(input_series_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
  dplyr::rename_with(~ gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(.x))))

policy_input <- readr::read_csv(input_policy_path, show_col_types = FALSE, name_repair = "unique_quiet") %>%
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
  arrange(month)

series_to_end <- series_monthly %>%
  filter(month <= as.Date("2025-06-01"))

# ------------------------------------------------------------
# Supplemental Figure A: shipments + policy lines
# ------------------------------------------------------------

shipments_monthly <- series_monthly %>%
  select(month, shipments = tx_raw) %>%
  filter(!is.na(shipments), month <= as.Date("2025-06-01")) %>%
  arrange(month) %>%
  mutate(x_num = as.numeric(month))

shipments_fit <- loess(
  shipments ~ x_num,
  data = shipments_monthly,
  span = 0.075,
  control = loess.control(surface = "direct"),
  na.action = na.exclude
)

shipments_monthly <- shipments_monthly %>%
  mutate(shipments_smooth = as.numeric(stats::predict(shipments_fit, newdata = data.frame(x_num = x_num))))

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
  filter(policy_month >= min(shipments_monthly$month, na.rm = TRUE), policy_month <= as.Date("2025-06-01")) %>%
  distinct(policy_month) %>%
  arrange(policy_month)

# Smoothed shipments series with policy date overlays.
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
    limits = c(min(shipments_monthly$month, na.rm = TRUE), as.Date("2025-07-01")),
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

# ------------------------------------------------------------
# Supplemental Figure B: seizures + cartel event lines
# ------------------------------------------------------------

seizures_monthly <- series_monthly %>%
  select(month, seizures_lbs = seizure_lbs_raw) %>%
  filter(!is.na(seizures_lbs), month <= as.Date("2025-06-01")) %>%
  arrange(month) %>%
  mutate(x_num = as.numeric(month))

seizures_fit <- loess(
  seizures_lbs ~ x_num,
  data = seizures_monthly,
  span = 0.075,
  control = loess.control(surface = "direct"),
  na.action = na.exclude
)

seizures_monthly <- seizures_monthly %>%
  mutate(seizures_smooth = as.numeric(stats::predict(seizures_fit, newdata = data.frame(x_num = x_num))))

cartel_event_dates <- tibble::tribble(
  ~event_month, ~event_group, ~event_label,
  as.Date("2016-01-01"), "Arrest/Capture", "El Chapo re-arrested in Los Mochis, Sinaloa",
  as.Date("2016-12-01"), "Seizure/Interdiction", "Two Sinaloa super tunnels found near Tijuana airport",
  as.Date("2017-01-01"), "Extradition/Transfer", "El Chapo extradited to the United States",
  as.Date("2019-02-01"), "Legal proceeding", "El Chapo convicted in New York federal court",
  as.Date("2019-10-01"), "Arrest/Capture", "Ovidio briefly captured and released in Culiacan",
  as.Date("2022-07-01"), "Arrest/Capture", "Rafael Caro Quintero captured by Mexico's navy",
  as.Date("2022-12-01"), "Arrest/Capture", "Antonio Oseguera Cervantes arrested in Mexico",
  as.Date("2023-01-01"), "Arrest/Capture", "Ovidio arrested in Culiacan in major raid",
  as.Date("2023-04-01"), "Legal proceeding", "US DOJ indictments against the Chapitos unsealed",
  as.Date("2023-09-01"), "Extradition/Transfer", "Ovidio extradited to the United States",
  as.Date("2023-11-01"), "Arrest/Capture", "Nestor Isidro Perez Salas arrested in Culiacan",
  as.Date("2024-07-01"), "Arrest/Capture", "El Mayo Zambada and Joaquin Guzman Lopez arrested",
  as.Date("2025-01-01"), "Policy", "US order/process designated major cartels as FTOs",
  as.Date("2025-02-01"), "Extradition/Transfer", "Mexico transferred 29 cartel leaders to US custody",
  as.Date("2025-07-01"), "Legal proceeding", "Ovidio pled guilty in US federal court in Chicago",
  as.Date("2026-02-01"), "Military operation", "Mexican forces reportedly killed CJNG leader El Mencho"
) %>%
  arrange(event_month)

# Smoothed seizures series with cartel-event date overlays.
plot_seizures_loess_event_lines <- ggplot(seizures_monthly, aes(x = month, y = seizures_smooth)) +
  geom_line(linewidth = 1.1, color = "#2c3e50", na.rm = TRUE) +
  geom_vline(
    data = cartel_event_dates,
    aes(xintercept = event_month),
    linetype = "dashed",
    linewidth = 0.45,
    color = "black",
    alpha = 0.85
  ) +
  scale_x_date(
    limits = c(min(cartel_event_dates$event_month, na.rm = TRUE), as.Date("2026-03-01")),
    date_breaks = "6 month",
    date_labels = "%b %Y",
    expand = expansion(mult = 0, add = 0)
  ) +
  labs(
    title = "Fentanyl seizures and major cartel events",
    subtitle = "Black dashed lines indicate cartel events listed in Table S2",
    x = "Month",
    y = "Fentanyl seizures (lbs)"
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# ------------------------------------------------------------
# Supplemental table: summary statistics through 2025-06
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Write outputs
# ------------------------------------------------------------

ggsave(
  filename = file.path(fig_dir, "plot_shipments_loess_policy_lines.png"),
  plot = plot_shipments_loess_policy_lines,
  width = 12,
  height = 6,
  dpi = 300
)

ggsave(
  filename = file.path(fig_dir, "plot_seizures_loess_event_lines.png"),
  plot = plot_seizures_loess_event_lines,
  width = 12,
  height = 6,
  dpi = 300
)

readr::write_csv(summary_stats, file.path(tab_dir, "summary_statistics_through_2025_06.csv"))

#cat("Wrote:", file.path(fig_dir, "plot_shipments_loess_policy_lines.png"), "\n")
#cat("Wrote:", file.path(fig_dir, "plot_seizures_loess_event_lines.png"), "\n")
#cat("Wrote:", file.path(tab_dir, "summary_statistics_through_2025_06.csv"), "\n")
