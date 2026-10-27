# STF that already carries geohash columns (here with a deliberately stale
# value for S01) must have them regenerated from lat/long, not duplicated.
# Relies on infer_geo_variables_for_eda() idempotency (study.wrangler >= 1.0.53).
assert <- function(study, output_dir) {
  site <- study %>% get_entity("site")
  data <- site %>% get_data()
  meta <- site %>% get_variable_metadata()

  geohash_cols <- paste0("geohash_", 1:6)
  expect_equal(sum(grepl("^geohash_", names(data))), 6)
  expect_equal(sum(meta$variable %in% geohash_cols), 6)

  s01 <- data %>% filter(Site.Id == "S01")
  expect_equal(s01$geohash_6, "kzf0tu")
}
