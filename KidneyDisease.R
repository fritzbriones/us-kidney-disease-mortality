# ==============================================================================
# PROJECT: US Kidney Disease Mortality by State
# PURPOSE: Validated choropleth (50 states + DC, Alaska & Hawaii as insets)
#          plus a ranked chart, coloured relative to the U.S. rate.
#
# INPUT  : mortality.xlsx (or Mortality.csv) with columns
#            Year, statescode, DeathRate   (one row per state + DC)
#          To update to a newer year, replace the file with the new year's
#          values (e.g. CDC "Stats of the States" or CDC WONDER export) and set
#          US_RATE below to that year's national age-adjusted rate.
# OUTPUT : Kidney Disease Map.png, kidney_disease_ranked.png,
#          data_validation_report.csv
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(readxl)
})

# National age-adjusted kidney disease death rate for the data year
# (2017: 13.0 per 100,000, NCHS Leading Causes of Death dataset bi63-dtpu).
US_RATE <- 13.0

# ---- 1. Read & validate --------------------------------------------------------
data_file <- if (file.exists("mortality.xlsx")) "mortality.xlsx" else "Mortality.csv"
raw <- if (grepl("xlsx$", data_file)) read_excel(data_file) else read_csv(data_file, show_col_types = FALSE)

mort <- raw |>
  transmute(
    Year = as.integer(Year),
    statescode = toupper(trimws(as.character(statescode))),
    DeathRate = as.numeric(DeathRate)
  )

study_codes <- sort(c(state.abb, "DC"))
problems <- c(
  if (n_distinct(mort$Year) != 1) "more than one Year in the file",
  if (anyDuplicated(mort$statescode)) "duplicate state codes",
  if (!setequal(mort$statescode, study_codes)) "state codes are not exactly the 50 states + DC",
  if (any(!is.finite(mort$DeathRate) | mort$DeathRate < 0)) "missing/negative DeathRate"
)
if (length(problems)) stop("Data validation failed: ", paste(problems, collapse = "; "))
YEAR <- unique(mort$Year)

states <- st_read("cb_2018_us_state_500k.shp", quiet = TRUE) |>
  filter(STUSPS %in% study_codes) |>
  st_transform(5070) |>
  left_join(mort, by = c("STUSPS" = "statescode"))
stopifnot(nrow(states) == 51, !anyNA(states$DeathRate))

write_csv(tibble(
  check = c("data_year", "records", "matched_features", "us_rate", "min", "max"),
  result = c(YEAR, nrow(mort), sum(!is.na(states$DeathRate)), US_RATE,
             min(mort$DeathRate), max(mort$DeathRate))
), "data_validation_report.csv")

# ---- 2. Move Alaska & Hawaii into insets ---------------------------------------
# Place each state so its centroid lands at a fixed target (EPSG:5070 metres)
# below the south-west of the contiguous US. Aleutian islands west of 170°W are
# dropped from the inset (they cross the antimeridian and would stretch the map).
inset <- function(g, scale, target) {
  geom <- st_geometry(g)
  ctr <- st_coordinates(st_centroid(st_union(geom)))[1, ]
  new <- (geom - ctr) * scale + target
  st_set_geometry(g, st_sfc(new, crs = st_crs(g)))
}
sf_use_s2(FALSE)
ak <- states |> filter(STUSPS == "AK") |> st_transform(4326) |>
  st_crop(c(xmin = -170, ymin = 50, xmax = -129, ymax = 72)) |>
  st_transform(5070) |> inset(0.35, c(-1.75e6, 0.45e6))
hi <- states |> filter(STUSPS == "HI") |> inset(1, c(-0.85e6, 0.30e6))
sf_use_s2(TRUE)
map_data <- bind_rows(states |> filter(!STUSPS %in% c("AK", "HI")), ak, hi)

# ---- 3. Map: diverging around the U.S. rate ------------------------------------
top <- mort |> slice_max(DeathRate, n = 5)
lim <- max(abs(range(mort$DeathRate) - US_RATE))

final_map <- ggplot(map_data) +
  geom_sf(aes(fill = DeathRate), color = "white", linewidth = 0.3) +
  scale_fill_gradient2(
    low = "#2166ac", mid = "#f7f7f7", high = "#b2182b", midpoint = US_RATE,
    limits = US_RATE + c(-lim, lim), oob = scales::squish,
    name = paste0("Age-adjusted deaths per 100,000 (U.S. = ", US_RATE, ")"),
    guide = guide_colorbar(title.position = "top", title.hjust = 0.5,
                           barwidth = unit(9, "cm"), barheight = unit(0.35, "cm"))
  ) +
  coord_sf(datum = NA) +
  labs(
    title = paste0("Kidney disease death rates by state, ", YEAR, ": highest in ",
                   paste(state.name[match(top$statescode[1:3], state.abb)], collapse = ", ")),
    subtitle = paste0("Highest: ", paste0(top$statescode, " ", top$DeathRate, collapse = ", "),
                      ".  Red = above the U.S. rate, blue = below."),
    caption = paste0("Source: CDC/NCHS, National Vital Statistics System, ", YEAR,
                     " (NCHS Leading Causes of Death dataset). Age-adjusted to the 2000 U.S. standard population.\n",
                     "Boundaries: U.S. Census Bureau cartographic boundary file (2018, 1:500k). Alaska and Hawaii shown as insets, not to scale.")
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(color = "grey30", margin = margin(t = 4, b = 10)),
    plot.caption = element_text(color = "grey45", size = 7.5, hjust = 0, margin = margin(t = 10)),
    plot.title.position = "plot", plot.caption.position = "plot",
    legend.position = "bottom",
    legend.title = element_text(size = 9, face = "bold"),
    plot.margin = margin(20, 20, 20, 20)
  )
ggsave("Kidney Disease Map.png", final_map, width = 12, height = 8, dpi = 300, bg = "white")

# ---- 4. Ranked chart -------------------------------------------------------------
ranked <- mort |>
  mutate(statescode = fct_reorder(statescode, DeathRate),
         side = if_else(DeathRate > US_RATE, "Above U.S.", "At/below U.S."))
n_above <- sum(mort$DeathRate > US_RATE)
hi_st <- mort |> slice_max(DeathRate, n = 1, with_ties = FALSE)
lo_st <- mort |> slice_min(DeathRate, n = 1, with_ties = FALSE)
ranked_plot <- ggplot(ranked, aes(DeathRate, statescode, fill = side)) +
  geom_col(width = 0.75) +
  geom_vline(xintercept = US_RATE, linetype = "dashed", color = "grey30") +
  annotate("text", x = US_RATE + 0.3, y = 3, label = paste0("U.S. ", US_RATE),
           hjust = 0, size = 3, color = "grey30") +
  geom_text(aes(label = DeathRate), hjust = -0.15, size = 2.4) +
  scale_fill_manual(values = c("Above U.S." = "#b2182b", "At/below U.S." = "#2166ac"), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(title = paste0(n_above, " of 51 jurisdictions are above the U.S. kidney disease death rate (", YEAR, ")"),
       subtitle = paste0("Highest (", hi_st$statescode, " ", hi_st$DeathRate, ") is ",
                         round(hi_st$DeathRate / lo_st$DeathRate, 1), "x the lowest (",
                         lo_st$statescode, " ", lo_st$DeathRate, ")"),
       x = "Age-adjusted deaths per 100,000", y = NULL,
       caption = "Source: CDC/NCHS, National Vital Statistics System.") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold"), plot.title.position = "plot",
        panel.grid.major.y = element_blank(), legend.position = "top",
        axis.text.y = element_text(size = 7), plot.caption = element_text(hjust = 0, color = "grey45"))
ggsave("kidney_disease_ranked.png", ranked_plot, width = 8, height = 9, dpi = 200, bg = "white")

message("Done: ", YEAR, " map and ranked chart written.")
