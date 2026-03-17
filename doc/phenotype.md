# phenotype wrangler

Input directory requirements

* exactly one tab-delimited file with one of these `".txt", ".tsv", ".csv", ".TXT", ".TSV", ".CSV"` extensions
* first column must be called `geneID` exactly
* `geneID` column must contain alphanumeric IDs (meaning that a number-only ID is not allowed)
  - TO DO: [more checks on gene IDs](https://github.com/VEuPathDB/vdi-plugin-wrangler/issues/2)
* `geneID` column must not contain duplicate entries (if you have more than one phenotype value, use multiple columns for these)
* there must also be at least one numeric column (for the phenotype value(s))
  - comma-separated thousands are accepted (e.g. `1,234` is read as `1234`); scientific notation is also supported (e.g. `1.23e-4`)
  - **if using CSV format**, commas in numbers will conflict with the CSV column delimiter — values must follow the CSV spec (e.g. quote the field: `"1,234"`) or use plain unformatted numbers
* **if** there is also a `gene` column it must contain exactly the same content as the `geneID` column (otherwise the wrangler will make a `gene` column like this anyway)

