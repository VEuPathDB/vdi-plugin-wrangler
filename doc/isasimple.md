# isasimple wrangler

_Note: this should be useful when updating https://clinepidb.org/ce/app/workspace/datasets/help or its dataExplorer/genomics site equivalent._

Accepts any flat tabular data file (CSV or tab-delimited) with no required columns.
A serial entity ID is generated automatically; all user-supplied columns become variables.

## Input file requirements

* exactly one `.csv`, `.tsv`, or `.txt` file (case-insensitive extension)
* column headers on the first row
* column names must be unique

Any file that was valid under the legacy ClinEpiDB upload rules will also be valid here — the old rules are a strict subset of what is accepted.

> **TODO:** Unique column names were not a documented requirement in legacy ClinEpiDB — the old system did not check for duplicates (likely an omission; unsure what the legacy fail mode was). Files with duplicate column names will currently produce a cryptic error. This should be caught early and reported as a clear validation message.

## Column name handling

Column names are sanitised using R's `make.names()` to produce valid R identifiers.
The **original** column name is always preserved in the `provider_label` metadata field and is used as the EDA display name.

The following transformations were verified empirically (`readr::read_csv(...) |> names() |> make.names(unique = TRUE)`):

| Original column name | Sanitised internal name | Notes |
|---|---|---|
| `sample name` | `sample.name` | spaces → `.` |
| `1st reading` | `X1st.reading` | leading digit → `X` prefix |
| `value (mg/L)` | `value..mg.L.` | special characters → `.` |
| `pH_7` | `pH_7` | underscores and alphanumerics unchanged |

Sanitised names are internal to R processing only — they are not exposed to end users. The display name shown in EDA always comes from the original column name via `provider_label`. Note that sanitised names *would* appear in an STF export, but the VDI import wranglers do not currently produce STF output.

> **Note for legacy ClinEpiDB users:** the old upload system converted spaces and special characters to underscores (`_`) and prefixed leading-digit column names with `_`. The new system uses `.` (dot) and `X` respectively, following standard R behaviour. The display name shown in EDA is always the original column name regardless.

## Data type inference

Types are inferred automatically from column content:

| Content | Inferred type |
|---|---|
| Numbers | `number` or `integer` |
| Dates in `YYYY-MM-DD` format | `date` |
| Everything else | `string` (categorical) |

Dates in any other format (e.g. `dd/mm/yyyy`, `mm-dd-yyyy`) are stored as categorical strings and will **not** be treated as dates in EDA.

## Geographic coordinate columns

Columns named with common latitude/longitude keywords (e.g. `latitude`, `lat`, `longitude`, `long`, `lng` — case-insensitive, with word boundaries or underscores as separators) are automatically assigned the appropriate EDA stable IDs:

* Latitude: `OBI_0001620`
* Longitude: `OBI_0001621`

This requires exactly one latitude column and one longitude column to be present. See [study-wrangler Entity-methods-eda.R](https://github.com/VEuPathDB/study-wrangler/blob/main/R/Entity-methods-eda.R) for full matching rules.

## No enforced size limits

The wrangler does not enforce limits on:

* number of columns
* number of rows
* cell value length

> **TODO:** Values longer than 1000 characters per cell pass wrangling successfully but may cause issues at database load time. A maximum cell-length validation step should be added to the `study-wrangler` EDA validation profile once the database limit is confirmed.

