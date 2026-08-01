library(dplyr)

library(tidyr)

library(gt)



# -- BEGIN TABLE_SETUP -- #
# Table 14.3.1 — Overall Summary of Treatment-Emergent Adverse Events
den0 <- adsl |> filter(SAFFL == "Y") |> mutate(ARM = TRT01A)
num0 <- adae |> filter(TRTEMFL == "Y") |> mutate(ARM = TRT01A)
den <- den0 |> bind_rows(mutate(den0, ARM = "Total"))
num <- num0 |> bind_rows(mutate(num0, ARM = "Total"))
bigN <- den |> group_by(ARM) |> summarise(bigN = n_distinct(USUBJID), .groups="drop")
# -- END TABLE_SETUP -- #

# -- BEGIN ROW1 -- #
# Subjects with any TEAE — distinct subjects
ae_1 <- num |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Subjects with any TEAE",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 1L, roworder = 1L, indent = 0L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW1 -- #

# -- BEGIN ROW2 -- #
# Subjects with any serious TEAE — distinct subjects
ae_2 <- num |> filter(AESER == "Y") |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Subjects with any serious TEAE",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 2L, roworder = 1L, indent = 0L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW2 -- #

# -- BEGIN ROW3 -- #
# Subjects with any drug-related TEAE — distinct subjects
ae_3 <- num |> filter(AEREL == "Y") |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Subjects with any drug-related TEAE",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 3L, roworder = 1L, indent = 0L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW3 -- #

# -- BEGIN ROW4 -- #
# Subjects with any TEAE leading to discontinuation — distinct subjects
ae_4 <- num |> filter(AEACN == "DRUG WITHDRAWN") |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Subjects with any TEAE leading to discontinuation",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 4L, roworder = 1L, indent = 0L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW4 -- #

# -- BEGIN ROW5 -- #
# TEAE by maximum severity — heading row
ae_5 <- tibble(ARM = character(), rowlabel = character(), value = character(),
              ord = integer(), roworder = integer(), indent = integer())
ae_5 <- bind_rows(ae_5, tibble(ARM = NA_character_, rowlabel = "TEAE by maximum severity",
              value = NA_character_, ord = 5L, roworder = 0L, indent = 0L))
# -- END ROW5 -- #

# -- BEGIN ROW6 -- #
# Mild — distinct subjects
ae_6 <- num |> filter(AESEV == "MILD") |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Mild",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 6L, roworder = 1L, indent = 1L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW6 -- #

# -- BEGIN ROW7 -- #
# Moderate — distinct subjects
ae_7 <- num |> filter(AESEV == "MODERATE") |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Moderate",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 7L, roworder = 1L, indent = 1L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW7 -- #

# -- BEGIN ROW8 -- #
# Severe — distinct subjects
ae_8 <- num |> filter(AESEV == "SEVERE") |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "Severe",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = 8L, roworder = 1L, indent = 1L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)
# -- END ROW8 -- #

# -- BEGIN REPORT -- #
report_long <- bind_rows(ae_1, ae_2, ae_3, ae_4, ae_5, ae_6, ae_7, ae_8) |> arrange(ord, roworder, ARM)
report_wide <- report_long |>
  pivot_wider(id_cols = c(ord, roworder, indent, rowlabel),
              names_from = ARM, values_from = value) |>
  arrange(ord, roworder) |>
  select(-ord, -roworder, -indent, -`NA`)

ae_table <- report_wide |>
  gt(rowname_col = "rowlabel") |>
  tab_header(title = "Table 14.3.1", subtitle = "Overall Summary of Treatment-Emergent Adverse Events") |>
  tab_source_note("TEAE = treatment-emergent adverse event.") |>
  tab_source_note("A subject is counted once within each row, regardless of the number of events.") |>
  tab_source_note("Percentages use the number of safety-population subjects per arm as denominator.")

ae_table
# -- END REPORT -- #
