# rnaseq-rc wrangler

Input directory requirements

* in the upload form, select one of these two count-file combinations, plus your sample metadata:
  - a sense-counts file **and** an antisense-counts file (a stranded pair), or
  - a single unstranded-counts file
  - do not mix the two styles, and do not select a stranded file without its pair
* every file's extension must be one of `.txt`, `.tsv`, `.csv` or `.tab`, matched case-insensitively (so `Sense-Counts.CSV` is accepted); the delimiter itself is sniffed from the file content
* you don't need to rename anything: you tell the form which role each file plays, and your files keep their original names all the way through — `HTSeq_output_run3.tsv` stays `HTSeq_output_run3.tsv`
* any additional `.txt`/`.tsv`/`.csv`/`.tab` file beyond the ones you selected is rejected rather than silently ignored, since an unexpected extra file is more likely a mistake than a deliberate addition

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

**Size limit: 100,000 bytes.** This comfortably accommodates a full Methods-section description of your samples (a typical manuscript Methods section is well under half this size), so it should never constrain a legitimate upload. If your file is larger, trim it down to just the sample-level metadata needed to group and label your samples — you don't need to include anything unrelated to sample identity or experimental grouping.

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
* whichever form you use, state the **units** for any numeric values (e.g. "age: 5 days", not "age: 5") — units are rarely recoverable from sample names alone, and the AI annotation step can only label a value it can actually interpret

An AI step reads this file together with the sample IDs found in your count file(s) and produces the structured sample annotation that can be used to define custom contrasts for differential expression analysis.

### Sample IDs that must appear in `sample-info`

If your count-file sample IDs are self-describing (e.g. `male_3h_rep1`, `female_6h_rep2`), they do not need to be repeated verbatim in `sample-info` — the experimental grouping can be read directly from the ID itself.

If your sample IDs are opaque codes or serial numbers (e.g. `S001`, `S002`), each one **must** appear somewhere in `sample-info`, because there is otherwise no way to recover which metadata belongs to which sample. If any opaque sample ID from your count files is not mentioned anywhere in `sample-info`, the import fails before any AI processing is attempted.

## Suitability for differential expression

Your sample metadata must describe at least one experimental factor that could define a comparison:

* at least 2 samples, and
* at least one attribute (besides the sample ID and its display label) that takes at least 2 different values across your samples

A dataset with only sample IDs and generic labels, and no other distinguishing metadata (e.g. treatment, genotype, timepoint, tissue), is rejected — there would be nothing to compare between groups.
