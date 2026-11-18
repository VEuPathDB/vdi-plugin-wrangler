# Real-world upload: headers contain spaces ("Pf ortholog", "Blood RGR"), which
# entity_from_file sanitizes with make.names(). The original header must survive
# as the display name / provider label, and display_order must follow file order.
assert <- function(study, output_dir) {
  meta <- study %>% get_entity("phenotype") %>% get_variable_metadata()
  order <- setNames(meta$display_order, meta$variable)
  expect_equal(order[c("gene", "description", "Pf.ortholog", "Blood.RGR")],
               c(gene = 1, description = 2, Pf.ortholog = 3, Blood.RGR = 4))
  expect_equal(meta$display_name[meta$variable == "Pf.ortholog"], "Pf ortholog")
}
