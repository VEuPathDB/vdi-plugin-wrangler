# rnaseq-rc wrangler

Input directory requirements

* one of these two count-file combinations, plus a `sample-info` file:
  - a `sense-counts` file **and** an `antisense-counts` file (a stranded pair), or
  - a single `unstranded-counts` file
  - do not mix the two styles, and do not upload a stranded file without its pair
* every file's extension must be one of `.txt`, `.tsv` or `.csv`, matched case-insensitively (so `Sense-Counts.CSV` is accepted); the delimiter itself is sniffed from the file content
* the filename **stem** must match exactly (`sense-counts`, `antisense-counts`, `unstranded-counts`, `sample-info`), matched case-insensitively — a file such as `counts.tsv` is rejected as unrecognised
* any other `.txt`/`.tsv`/`.csv` file in the input directory is rejected rather than silently ignored, since an unexpected extra file is more likely a misnamed count file than a deliberate extra

## Counts file layout

* genes as rows, samples as columns
* the first column is treated as the gene ID **by its position**, regardless of what its header cell says — production HTSeq output leaves that header cell empty
* every other cell must be a whole, non-negative number with no thousands separators:
  - blank cells, non-numeric text, fractional values (e.g. `1.5`), negative values (e.g. `-5`), and thousands-separated values (e.g. `1,234`) are all rejected
* rows whose gene ID starts with `__` are recognised as HTSeq's own summary rows (`__no_feature`, `__ambiguous`, `__too_low_aQual`, …) and are silently dropped before validation
* gene IDs must not repeat within a file
* for a stranded pair, `sense-counts` and `antisense-counts` must describe the exact same set of sample columns and the exact same set of gene rows (column/row order does not matter) — a mismatch in either is rejected rather than silently dropped

## The `sample-info` file

Required, and must not be empty. It describes your samples in whatever form is most convenient — it does not need to be a structured table. Accepted forms include:

* a **horizontal table** (one row per sample, one column per attribute), as TSV or CSV:
  ```
  sample	treatment	timepoint
  S1	infected	24
  S2	infected	24
  S3	control	24
  S4	control	24
  ```
* a **vertical (transposed) table** (one column per sample, one row per attribute), as TSV or CSV:
  ```
  sample	S1	S2	S3	S4
  treatment	infected	infected	control	control
  timepoint	24	24	24	24
  ```
* **free text** describing the samples in prose, e.g. "Samples S1 and S2 were infected; S3 and S4 were untreated controls. All were harvested 24 hours post-infection."
* an **article methods paragraph**, copied as-is from a manuscript's methods section

An AI step reads this file together with the sample IDs found in your count file(s) and produces the structured sample annotation that can be used to define custom contrasts for differential expression analysis.

### Sample IDs that must appear in `sample-info`

If your count-file sample IDs are self-describing (e.g. `male_3h_rep1`, `female_6h_rep2`), they do not need to be repeated verbatim in `sample-info` — the experimental grouping can be read directly from the ID itself.

If your sample IDs are opaque codes or serial numbers (e.g. `S001`, `S002`), each one **must** appear somewhere in `sample-info`, because there is otherwise no way to recover which metadata belongs to which sample. If any opaque sample ID from your count files is not mentioned anywhere in `sample-info`, the import fails before any AI processing is attempted.

## Suitability for differential expression

Your sample metadata must describe at least one experimental factor that could define a comparison:

* at least 2 samples, and
* at least one attribute (besides the sample ID and its display label) that takes at least 2 different values across your samples

A dataset with only sample IDs and generic labels, and no other distinguishing metadata (e.g. treatment, genotype, timepoint, tissue), is rejected — there would be nothing to compare between groups.
