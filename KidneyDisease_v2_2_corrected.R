# ==============================================================================
# PROJECT: US Kidney Disease Mortality Rate Map
# VERSION: 2.2.1
# PURPOSE: Reproducible choropleth of 2017 age-adjusted kidney disease mortality
# GEOGRAPHY: Contiguous United States + District of Columbia
# PROJECTION: NAD83 / Conus Albers (EPSG:5070)
# ==============================================================================

# 0. CONFIGURATION -------------------------------------------------------------
# Run this script from the repository/project folder containing the files below.

required_files <- c("cb_2018_us_state_500k.shp", "mortality.xlsx")
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop(
    "Missing required input file(s): ", paste(missing_files, collapse = ", "),
    "\nSet your R working directory to the project folder and try again."
  )
}

required_packages <- c("tidyverse", "sf", "readxl", "viridis")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(
    "Install missing package(s) first: ",
    paste(missing_packages, collapse = ", "),
    "\nRun: install.packages(c(",
    paste(sprintf('"%s"', missing_packages), collapse = ", "), "))"
  )
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(readxl)
  library(viridis)
})

output_file <- "Kidney Disease Map.png"
audit_file <- "data_validation_report.csv"

# 1. READ SOURCE DATA ----------------------------------------------------------
message("Reading state boundaries and mortality data...")

state_boundaries_all <- st_read("cb_2018_us_state_500k.shp", quiet = TRUE)
mortality_raw <- read_excel("mortality.xlsx")

# Check required fields before any transformation.
required_boundary_fields <- c("STUSPS")
required_mortality_fields <- c("statescode", "DeathRate")

# IMPORTANT: validate against state_boundaries_all, which is the object
# actually read from the shapefile. state_boundaries is created below.
missing_boundary_fields <- setdiff(
  required_boundary_fields, names(state_boundaries_all)
)
missing_mortality_fields <- setdiff(
  required_mortality_fields, names(mortality_raw)
)

if (length(missing_boundary_fields) > 0) {
  stop("Boundary file is missing field(s): ",
       paste(missing_boundary_fields, collapse = ", "))
}
if (length(missing_mortality_fields) > 0) {
  stop("Mortality workbook is missing field(s): ",
       paste(missing_mortality_fields, collapse = ", "))
}
if (is.na(st_crs(state_boundaries_all))) {
  stop("The boundary shapefile has no coordinate reference system (CRS).")
}

# Keep only the 50 states and District of Columbia. Census state-boundary
# files may also contain territories; they are outside this study's scope.
study_codes <- sort(c(state.abb, "DC"))
state_boundaries <- state_boundaries_all %>%
  mutate(STUSPS = toupper(trimws(as.character(STUSPS)))) %>%
  filter(STUSPS %in% study_codes)

if (!all(study_codes %in% state_boundaries$STUSPS)) {
  absent <- setdiff(study_codes, state_boundaries$STUSPS)
  stop("Boundary shapefile is missing study area code(s): ",
       paste(absent, collapse = ", "))
}

# 2. STANDARDIZE AND VALIDATE JOIN KEYS ----------------------------------------
state_boundaries <- state_boundaries %>%
  mutate(STUSPS = toupper(trimws(as.character(STUSPS))))

mortality_data <- mortality_raw %>%
  mutate(
    statescode = toupper(trimws(as.character(statescode))),
    DeathRate = suppressWarnings(as.numeric(DeathRate))
  )

if (any(is.na(state_boundaries$STUSPS) | state_boundaries$STUSPS == "")) {
  stop("The boundary file contains missing or blank state abbreviations.")
}
if (any(is.na(mortality_data$statescode) | mortality_data$statescode == "")) {
  stop("The mortality data contain missing or blank state abbreviations.")
}

duplicate_boundary_codes <- unique(
  state_boundaries$STUSPS[duplicated(state_boundaries$STUSPS)]
)
duplicate_mortality_codes <- unique(
  mortality_data$statescode[duplicated(mortality_data$statescode)]
)
if (length(duplicate_boundary_codes) > 0) {
  stop("Duplicate state codes in boundary file: ",
       paste(duplicate_boundary_codes, collapse = ", "))
}
if (length(duplicate_mortality_codes) > 0) {
  stop("Duplicate state codes in mortality data: ",
       paste(duplicate_mortality_codes, collapse = ", "))
}

if (any(!is.finite(mortality_data$DeathRate))) {
  bad_codes <- mortality_data$statescode[!is.finite(mortality_data$DeathRate)]
  stop("Missing or non-numeric DeathRate value(s) for: ",
       paste(bad_codes, collapse = ", "))
}
if (any(mortality_data$DeathRate < 0)) {
  stop("DeathRate contains negative values; check the source data.")
}

boundary_codes <- sort(unique(state_boundaries$STUSPS))
mortality_codes <- sort(unique(mortality_data$statescode))
missing_from_mortality <- setdiff(boundary_codes, mortality_codes)
not_in_boundaries <- setdiff(mortality_codes, boundary_codes)

if (length(missing_from_mortality) > 0) {
  stop("No mortality record found for boundary code(s): ",
       paste(missing_from_mortality, collapse = ", "))
}
if (length(not_in_boundaries) > 0) {
  warning("Mortality code(s) not represented in the boundary file: ",
          paste(not_in_boundaries, collapse = ", "))
}

# 3. JOIN AND VERIFY RECORD COUNTS ---------------------------------------------
joined_data <- state_boundaries %>%
  left_join(mortality_data, by = c("STUSPS" = "statescode"))

if (nrow(joined_data) != nrow(state_boundaries)) {
  stop("Join changed the number of geographic features. Check duplicate keys.")
}
if (anyNA(joined_data$DeathRate)) {
  unmatched <- joined_data$STUSPS[is.na(joined_data$DeathRate)]
  stop("Mortality join produced missing rate(s) for: ",
       paste(unmatched, collapse = ", "))
}

audit_report <- tibble(
  check = c(
    "Boundary features",
    "Mortality records",
    "Unique boundary codes",
    "Unique mortality codes",
    "Matched geographic features",
    "Unmatched boundary codes",
    "Mortality codes absent from boundary file",
    "Missing/non-finite mortality rates"
  ),
  result = c(
    nrow(state_boundaries),
    nrow(mortality_data),
    length(boundary_codes),
    length(mortality_codes),
    sum(!is.na(joined_data$DeathRate)),
    length(missing_from_mortality),
    length(not_in_boundaries),
    sum(!is.finite(mortality_data$DeathRate))
  )
)
write_csv(audit_report, audit_file)
message("Data validation passed. Report saved to: ", audit_file)

# 4. DEFINE MAP COVERAGE AND PROJECT -------------------------------------------
# AK and HI are retained in validation but excluded from this contiguous-US map.
map_data <- joined_data %>%
  filter(!STUSPS %in% c("AK", "HI")) %>%
  st_transform(crs = 5070)

if (nrow(map_data) == 0) {
  stop("No geographic features remain after selecting the contiguous US.")
}

# 5. BUILD PRESENTATION MAP ----------------------------------------------------
map_title <- "Kidney Disease Mortality by State (2017)"
map_subtitle <- "Age-adjusted mortality rate per 100,000 population"
map_caption <- paste(
  "Source: CDC/NVSS Underlying Cause of Death, WONDER (2017);",
  "U.S. Census Bureau 2018 state boundaries (500k).",
  "Map coverage: contiguous United States and District of Columbia.",
  sep = "\n"
)

final_map <- ggplot(map_data) +
  geom_sf(aes(fill = DeathRate), color = "white", linewidth = 0.35) +
  scale_fill_viridis_c(
    option = "plasma",
    direction = -1,
    name = "Deaths per 100,000",
    na.value = "#E0E0E0",
    labels = scales::label_number(accuracy = 0.1),
    guide = guide_colorbar(
      title.position = "top",
      title.hjust = 0.5,
      barwidth = grid::unit(9, "cm"),
      barheight = grid::unit(0.35, "cm")
    )
  ) +
  labs(
    title = stringr::str_wrap(map_title, width = 48),
    subtitle = map_subtitle,
    caption = map_caption
  ) +
  coord_sf(
    xlim = c(-2500000, 2500000),
    ylim = c(200000, 3200000),
    expand = FALSE,
    datum = NA
  ) +
  theme_void() +
  theme(
    plot.title.position = "plot",
    plot.title = element_text(
      face = "bold", size = 19, hjust = 0,
      lineheight = 1.08, margin = margin(b = 8)
    ),
    plot.subtitle = element_text(
      color = "grey35", size = 11, hjust = 0,
      margin = margin(b = 14)
    ),
    plot.caption = element_text(
      color = "grey40", size = 8, hjust = 0,
      lineheight = 1.15, margin = margin(t = 12)
    ),
    legend.position = "bottom",
    legend.title = element_text(size = 9, face = "bold"),
    legend.text = element_text(size = 8),
    plot.margin = margin(t = 26, r = 30, b = 24, l = 30)
  )

# 6. EXPORT --------------------------------------------------------------------
# 14 x 9 inches at 300 dpi = 4200 x 2700 pixels.
ggsave(
  filename = output_file,
  plot = final_map,
  width = 14,
  height = 9,
  units = "in",
  dpi = 300,
  bg = "white",
  limitsize = FALSE
)

message("Map exported: ", normalizePath(output_file, winslash = "/", mustWork = FALSE))
message("Included geographic features: ", nrow(map_data))
message("Excluded from display (but retained in validation): AK and HI")
message("Completed. Review the map and data_validation_report.csv before publication.")
