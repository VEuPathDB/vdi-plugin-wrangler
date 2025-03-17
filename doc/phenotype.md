# phenotype wrangler

Input directory requirements

* exactly one tab-delimited file with `.txt` or `.tsv` extension
  - TO DO: [add CSV file handling](https://github.com/VEuPathDB/study-wrangler/issues/30)
* first column must be called `geneID` exactly
* `geneID` column must contain alphanumeric IDs
  - TO DO: [more checks on gene IDs](https://github.com/VEuPathDB/vdi-plugin-wrangler/issues/2)
* `geneID` column must not contain duplicate entries (if you have more than one phenotype value, use multiple columns for these)
* there must also be at least one numeric column (for the phenotype value(s))
* **if** there is also a `gene` column it must contain exactly the same content as the `geneID` column (otherwise the wrangler will make a `gene` column like this anyway)

