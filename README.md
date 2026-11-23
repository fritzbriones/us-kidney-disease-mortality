# U.S. Kidney Disease Mortality by State (2017)

![Kidney disease death rates by state, 2017](Kidney%20Disease%20Map.png)

## Key findings

- The U.S. age-adjusted kidney disease death rate was **13.0 per 100,000** in 2017.
- **23 of 51 jurisdictions** (50 states + DC) were above the national rate.
- The highest rates form a belt across the **Deep South and lower Midwest**: Mississippi 21.7, Louisiana 20.6, Arkansas 19.7, Missouri 19.6, Kentucky 19.4.
- The lowest were Vermont 3.3, Washington 5.3 and Arizona 6.2. Mississippi's rate is **6.6×** Vermont's.
- **Public-health takeaway:** kidney disease screening and early-care programmes have the most potential impact in the high-rate belt. Vermont's unusually low value is worth checking against neighbouring years before drawing conclusions.

![States ranked against the U.S. rate](kidney_disease_ranked.png)

## Data source and verification

- **Death rates:** CDC/NCHS, *NCHS – Leading Causes of Death: United States* (data.cdc.gov dataset `bi63-dtpu`), cause "Kidney disease" (nephritis, nephrotic syndrome and nephrosis), year 2017. Rates are age-adjusted to the 2000 U.S. standard population.
- **Verified:** all 51 values in `mortality.xlsx` / `Mortality.csv` match the CDC dataset exactly (checked 2026-11-23), and the national rate of 13.0 also matches.
- **Boundaries:** U.S. Census Bureau cartographic boundary file, 2018, 1:500k (`cb_2018_us_state_500k`).

### Why 2017?

The `bi63-dtpu` dataset ends in 2017. CDC has newer state rates (2024) on its
[Stats of the States – Kidney Disease](https://www.cdc.gov/nchs/state-stats/deaths/kidney-disease.html) page.
To update the map:

1. Open that page, switch to the table view and copy the state rates (or export them from CDC WONDER).
2. Replace the `Year`, `statescode` and `DeathRate` columns in `mortality.xlsx` with the new values.
3. Set `US_RATE` at the top of `KidneyDisease.R` to that year's national rate.
4. Run the script. The title, subtitle, colours and ranked chart all update from the data.

## Method

- The map colours each state relative to the U.S. rate: **red is above, blue is below**. That shows where the burden is unusually high, not just raw values.
- Alaska and Hawaii are shown as insets (not to scale). The far-western Aleutian Islands are left out of the inset.
- The script stops if the file doesn't have exactly the 50 states + DC, has duplicates, has missing or negative rates, or mixes years. It writes `data_validation_report.csv`.
- Projection: NAD83 / Conus Albers (EPSG:5070).

## Reproduce

```r
install.packages(c("tidyverse", "sf", "readxl"))
source("KidneyDisease.R")
```

Outputs: `Kidney Disease Map.png`, `kidney_disease_ranked.png`, `data_validation_report.csv`.

## Files

| File | Description |
|---|---|
| `KidneyDisease.R` | Validates the data, then draws the map and the ranked chart |
| `mortality.xlsx` | 2017 rates by state (the script's input) |
| `Mortality.csv` | Same data as plain text |
| `cb_2018_us_state_500k.*` | Census state boundaries |
| `Kidney Disease Map.png`, `kidney_disease_ranked.png` | Outputs |
| `data_validation_report.csv` | Validation summary |

## Limitations

- Age-adjusted rates remove differences in age structure but not other factors such as race/ethnicity mix, diabetes prevalence or access to dialysis.
- State rates are based on the underlying cause written on death certificates, and certification practices differ between states.
