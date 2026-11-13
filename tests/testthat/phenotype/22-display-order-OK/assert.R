assert <- function(study, output_dir) {
  meta <- study %>% get_entity("phenotype") %>% get_variable_metadata()
  order <- setNames(meta$display_order, meta$variable)
  expect_equal(order[c("gene", "zeta", "alpha", "mid")],
               c(gene = 1, zeta = 2, alpha = 3, mid = 4))
}
