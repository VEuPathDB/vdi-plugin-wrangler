# Headers contain spaces and punctuation ("cheese name", "age (months)"), which
# entity_from_file sanitizes with make.names(). The original headers must survive
# as display names and display_order must follow file order.
assert <- function(study, output_dir) {
  meta <- study %>% get_entity("record") %>% get_variable_metadata()
  display <- setNames(meta$display_name, meta$variable)
  expect_equal(display[["cheese.name"]], "cheese name")
  expect_equal(display[["milk.type"]], "milk type")
  expect_equal(display[["age..months."]], "age (months)")
  expect_equal(display[["avg.price.eur.kg"]], "avg price eur/kg")
  order <- setNames(meta$display_order, meta$variable)
  expect_equal(order[c("cheese.name", "country", "avg.price.eur.kg")],
               c(cheese.name = 1, country = 2, avg.price.eur.kg = 12))
}
