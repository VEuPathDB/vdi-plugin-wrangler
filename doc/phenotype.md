# phenotype wrangler

Input directory requirements

* exactly one tab-delimited file with one of these `".txt", ".tsv", ".csv", ".TXT", ".TSV", ".CSV"` extensions (the VDI config for `phenotype` allows `.txt`, `.tsv` and `.csv`)
* first column must be called `gene` exactly
* `gene` column must contain alphanumeric IDs (meaning that a number-only ID is not allowed)
  - TO DO: [more checks on gene IDs](https://github.com/VEuPathDB/vdi-plugin-wrangler/issues/2)
* `gene` column must not contain duplicate or empty entries (if you have more than one phenotype value, use multiple columns for these)
* there must also be at least one other numeric or categorical (text) column (for the phenotype value(s)); a mix of the two is allowed. Date-only files are not accepted
  - comma-separated thousands are accepted (e.g. `1,234` is read as `1234`); scientific notation is also supported (e.g. `1.23e-4`)
  - **if using CSV format**, commas in numbers will conflict with the CSV column delimiter — values must follow the CSV spec (e.g. quote the field: `"1,234"`) or use plain unformatted numbers
* the file must not contain a column called `geneID__` (reserved: the wrangler copies the `gene` column into this internal ID column)

The `gene` column is kept as a regular variable with `stable_id` `VEUPATHDB_GENE_ID`. Files from before this change, with `geneID` as the first column, must be re-uploaded with the column renamed to `gene`.
