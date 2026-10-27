# Geo STF uploads carry only lat/long; the wrangler must infer the EDA geo
# metadata and geohash (geoaggregator) variables itself before export.
assert <- function(study, output_dir) {
  site <- study %>% get_entity("site")
  meta <- site %>% get_variable_metadata()
  stable <- setNames(meta$stable_id, meta$variable)

  expect_equal(stable[["Latitude"]],  "OBI_0001620")
  expect_equal(stable[["Longitude"]], "OBI_0001621")

  geohash_cols <- paste0("geohash_", 1:6)
  expect_true(all(geohash_cols %in% names(site %>% get_data())), label = "geohash columns generated")
  expect_true(all(geohash_cols %in% meta$variable), label = "geohash variables have metadata")

  # Non-geo entities are left without geohash columns
  sample <- study %>% get_entity("sample")
  expect_false(any(geohash_cols %in% names(sample %>% get_data())))
}
