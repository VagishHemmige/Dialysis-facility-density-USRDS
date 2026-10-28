# Purpose: draw Figure 1 (cohort flow) and Figure 2 (HSA maps), and export
#   them to figures/.
# Needs: cohort_fc (create_cohort.R); hsa_crosswalk, hsa_population,
#   hsa_benchmarks, hsa_boundaries (download_public_data.R); figures_dir.
# Produces: PNG files in figures/ (gitignored until checked and cleared).
#   Figure 2 uses only public data (CMS, ACS, Dartmouth).

## ---- draw-cohort-flowchart
dir.create(figures_dir, showWarnings = FALSE)
cohort_fc |>
  fc_draw(big.mark = ",") |>
  fc_export(
    file.path(figures_dir, "figure_1_cohort_flow.png"),
    width = 3000, height = 4200, res = 300
  )

## ---- compute-hsa-map-data
# HSA facility and station density on 1 January of the map year, from public
# data only: CMS facilities (usRds), Dartmouth crosswalk, ACS population.
map_year <- max(study_years)
map_date <- make_date(map_year, 1, 1)

hsa_map_data <- summarize_dialysis_facilities(
  area_crosswalk = select(hsa_crosswalk, zip, year, hsanum),
  area_id = "hsanum"
) |>
  filter(
    year == map_year,
    valid_from <= map_date,
    is.na(valid_to) | valid_to >= map_date
  ) |>
  select(hsanum, centers, stations) |>
  right_join(
    filter(hsa_population, year == map_year),
    by = "hsanum",
    relationship = "one-to-one"
  ) |>
  mutate(
    # HSAs with no facility on the map date have 0, not missing
    across(c(centers, stations), \(count) coalesce(count, 0L)),
    center_density = centers / hsa_population * density_per_population,
    station_density = stations / hsa_population * density_per_population
  ) |>
  left_join(hsa_benchmarks, by = "hsanum", relationship = "one-to-one")

contiguous_hsas <- hsa_crosswalk |>
  filter(year == map_year, !hsa_state %in% c("AK", "HI")) |>
  distinct(hsanum)

hsa_map <- hsa_boundaries |>
  semi_join(contiguous_hsas, by = "hsanum") |>
  left_join(hsa_map_data, by = "hsanum", relationship = "many-to-one")

## ---- draw-hsa-maps
# One panel per map (map_panel() in functions.R)
figure_2 <- list(
  a = map_panel(
    hsa_map, "center_density",
    title = "A. Dialysis facility density",
    legend = "Facilities per\n100,000"
  ),
  b = map_panel(
    hsa_map, "station_density",
    title = "B. Dialysis station density",
    legend = "Stations per\n100,000"
  ),
  c = map_panel(
    hsa_map, "hsa_percent_eye_exam",
    title = "C. Annual eye exams among enrollees with diabetes, 2015",
    legend = "Percent"
  )
)

iwalk(figure_2, function(plot, panel) {
  ggsave(
    file.path(figures_dir, str_glue("figure_2{panel}_hsa_map.png")),
    plot,
    width = 9, height = 5.5, dpi = 300, bg = "white"
  )
})
