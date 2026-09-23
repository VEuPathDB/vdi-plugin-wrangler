# stf wrangler

Thin wrapper around `study_from_stf()` from the study.wrangler package. Unlike the other
datatypes, STF input isn't a free-form file uploaded by an end user — it's the package's own
native serialization format, expected to be produced by a trusted internal pipeline (or a
site administrator following the format spec) rather than typed or exported by hand.

The canonical format specification lives in the study.wrangler repo:
[Study-Transfer-Format-STF.md](https://github.com/VEuPathDB/study-wrangler/blob/main/STF_documentation/Study-Transfer-Format-STF.md)
(still a work in progress — treat it as the source of truth over anything summarised here).

## Input directory requirements

Two layouts are accepted:

* **With a `study.yaml`** — lists the entities to load by name (`entities: [household, participant, ...]`).
  For each entry, the wrangler looks for `entity-<name>.tsv` and, optionally, `entity-<name>.yaml`
  (variable/category metadata; if omitted, metadata is inferred from the TSV header alone).
* **Without a `study.yaml`** — every `entity-*.tsv` file present is loaded (again with an optional
  matching `entity-<name>.yaml`), but the resulting study has no name or other study-level metadata.

Each `entity-*.tsv` file is either wide or tall format, distinguished by a `\\ Descriptors` (or
`Descriptors \\`) marker in the header row — see the canonical spec for the full column-layout
rules (ID columns, parent/child references, etc.).

## Encoding requirement

All `.tsv`, `.yaml`, and `.yml` files in the input directory must be valid UTF-8. This is checked
explicitly before wrangling begins, and the whole import fails with a clear message naming any
non-UTF-8 file(s) found.

This is deliberately stricter than the phenotype/isasimple wranglers, which sniff and tolerate
legacy encodings (Windows-1252, ISO-8859-1, UTF-16) because their input is an arbitrary file
uploaded by an end user. STF input is expected to always originate from trusted tooling that can
reasonably guarantee UTF-8 output, so rather than add the same encoding-tolerance machinery here,
a bad encoding is treated as a bug in the producing pipeline and reported as a hard failure —
`study_from_stf()` itself has no encoding awareness at all, and would otherwise silently
mis-decode non-UTF-8 bytes rather than error.

> **Note:** per-entity validation errors (e.g. a malformed YAML `categories` section, or an entity
> that fails EDA validation) are currently reported with less file-level attribution than for
> phenotype/isasimple — see [study-wrangler `entity_from_stf()`](https://github.com/VEuPathDB/study-wrangler/blob/main/R/entity_from_stf.R)
> for the underlying error messages. Acceptable for now given the trusted-pipeline assumption
> above; revisit if STF import sees broader or less-trusted use.
