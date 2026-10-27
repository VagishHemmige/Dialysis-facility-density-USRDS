# Purpose: draw Figure 1 (cohort flow) and Figure 2 (HSA maps), and export
#   them to figures/.
# Needs: cohort_fc (create_cohort.R); hsa_crosswalk, hsa_population,
#   hsa_benchmarks, hsa_boundaries (download_public_data.R); figures_dir.
# Produces: PNG files in figures/ (gitignored until checked and cleared).
#   Figure 2 uses only public data (CMS, ACS, Dartmouth).

## ---- draw-cohort-flowchart
dir.create(figures_dir, showWarnings = FALSE)
cohort_fc |>
  fc_draw() |>
  fc_export(file.path(figures_dir, "figure_1_cohort_flow.png"),
            width = 3000, height = 4200, res = 300)

## ---- compute-hsa-map-data
# HSA facility and station density on 1 January of the map year, from public
# data only: CMS facilities (usRds), Dartmouth crosswalk, ACS population.
map_year <- max(study_years)
map_date <- as.Date(paste0(map_year, "-01-01"))

hsa_map_data <- summarize_dialysis_facilities(
  area_crosswalk = select(hsa_crosswalk, zip, year, hsanum),
  area_id = "hsanum"
) |>
  filter(year == map_year, valid_from <= map_date, is.na(valid_to) | valid_to >= map_date) |>
  select(hsanum, centers, stations) |>
  right_join(filter(hsa_population, year == map_year), by = "hsanum",
             relationship = "one-to-one") |>
  mutate(
    across(c(centers, stations), ~ coalesce(.x, 0L)),
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
map_panel <- function(map, fill, title, legend) {
  ggplot(map) +
    geom_sf(aes(fill = .data[[fill]]), color = NA) +
    scale_fill_viridis_c(name = legend, na.value = "grey85") +
    coord_sf(crs = 5070) +
    labs(title = title) +
    theme_void()
}

figure_2 <- list(
  a = map_panel(hsa_map, "center_density", "A. Dialysis facility density", "Facilities per\n100,000"),
  b = map_panel(hsa_map, "station_density", "B. Dialysis station density", "Stations per\n100,000"),
  c = map_panel(hsa_map, "hsa_percent_eye_exam",
                "C. Annual eye exams among enrollees with diabetes, 2015", "Percent")
)

iwalk(figure_2, function(plot, panel) {
  ggsave(file.path(figures_dir, paste0("figure_2", panel, "_hsa_map.png")), plot,
         width = 9, height = 5.5, dpi = 300, bg = "white")
})
