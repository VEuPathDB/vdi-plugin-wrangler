assert <- function(study, output_dir) {
  entity <- study %>% get_entity("phenotype")
  meta <- entity %>% get_variable_metadata()
  stable <- setNames(meta$stable_id, meta$variable)
  expect_equal(stable[["gene"]], "VEUPATHDB_GENE_ID")
  expect_equal(entity %>% get_id_column_metadata() %>% pull(variable), "geneID__")
}
