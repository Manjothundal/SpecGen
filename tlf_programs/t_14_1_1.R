library(dplyr)

library(tidyr)

library(gt)



# -- BEGIN TABLE_SETUP -- #
# Table 14.1.1 — Summary of Demographic and Baseline Characteristics
# Population: keep only SAFFL == "Y"; ARM = treatment arm, plus a Total copy.
tab0 <- adsl |>
  filter(SAFFL == "Y") |>
  mutate(ARM = TRT01A)

tab <- tab0 |>
  bind_rows(mutate(tab0, ARM = "Total"))

# denominator N per arm (distinct subjects) for categorical percentages
bigN <- tab |> group_by(ARM) |> summarise(bigN = n_distinct(USUBJID), .groups = "drop")
# -- END TABLE_SETUP -- #

# -- BEGIN AGE -- #
# Age (years) — continuous display rows
d_AGE <- tab |>
  group_by(ARM) |>
  summarise(
    n = sum(!is.na(AGE)),
    mean = mean(AGE, na.rm = TRUE),
    sd = sd(AGE, na.rm = TRUE),
    median = median(AGE, na.rm = TRUE),
    min = min(AGE, na.rm = TRUE),
    max = max(AGE, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    `n` = as.character(n),
    `Mean (SD)` = paste0(formatC(mean, format="f", digits=1),
                         " (", formatC(sd, format="f", digits=2), ")"),
    `Median` = formatC(median, format="f", digits=1),
    `Min, Max` = paste0(formatC(min, format="f", digits=1), ", ",
                        formatC(max, format="f", digits=1))
  ) |>
  select(ARM, `n`, `Mean (SD)`, `Median`, `Min, Max`) |>
  pivot_longer(-ARM, names_to = "rowlabel", values_to = "value") |>
  mutate(ord = 1, grouplabel = "Age (years)",
         roworder = match(rowlabel, c("n","Mean (SD)","Median","Min, Max")))
# -- END AGE -- #

# -- BEGIN AGEGR1 -- #
# Age Group, n (%) — categorical n (%) display rows
d_AGEGR1 <- tab |>
  group_by(ARM, AGEGR1) |>
  summarise(n = n(), .groups = "drop") |>
  left_join(bigN, by = "ARM") |>
  mutate(
    rowlabel = as.character(AGEGR1),
    value = ifelse(bigN > 0,
                   paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"),
                   as.character(n)),
    ord = 2, grouplabel = "Age Group, n (%)",
    roworder = 100 + as.integer(factor(AGEGR1))
  ) |>
  select(ARM, rowlabel, value, ord, grouplabel, roworder)
# -- END AGEGR1 -- #

# -- BEGIN SEX -- #
# Sex, n (%) — categorical n (%) display rows
d_SEX <- tab |>
  group_by(ARM, SEX) |>
  summarise(n = n(), .groups = "drop") |>
  left_join(bigN, by = "ARM") |>
  mutate(
    rowlabel = as.character(SEX),
    value = ifelse(bigN > 0,
                   paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"),
                   as.character(n)),
    ord = 3, grouplabel = "Sex, n (%)",
    roworder = 100 + as.integer(factor(SEX))
  ) |>
  select(ARM, rowlabel, value, ord, grouplabel, roworder)
# -- END SEX -- #

# -- BEGIN RACE -- #
# Race, n (%) — categorical n (%) display rows
d_RACE <- tab |>
  group_by(ARM, RACE) |>
  summarise(n = n(), .groups = "drop") |>
  left_join(bigN, by = "ARM") |>
  mutate(
    rowlabel = as.character(RACE),
    value = ifelse(bigN > 0,
                   paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"),
                   as.character(n)),
    ord = 4, grouplabel = "Race, n (%)",
    roworder = 100 + as.integer(factor(RACE))
  ) |>
  select(ARM, rowlabel, value, ord, grouplabel, roworder)
# -- END RACE -- #

# -- BEGIN BMIBL -- #
# Baseline BMI (kg/m2) — continuous display rows
d_BMIBL <- tab |>
  group_by(ARM) |>
  summarise(
    n = sum(!is.na(BMIBL)),
    mean = mean(BMIBL, na.rm = TRUE),
    sd = sd(BMIBL, na.rm = TRUE),
    median = median(BMIBL, na.rm = TRUE),
    min = min(BMIBL, na.rm = TRUE),
    max = max(BMIBL, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    `n` = as.character(n),
    `Mean (SD)` = paste0(formatC(mean, format="f", digits=1),
                         " (", formatC(sd, format="f", digits=2), ")"),
    `Median` = formatC(median, format="f", digits=1),
    `Min, Max` = paste0(formatC(min, format="f", digits=1), ", ",
                        formatC(max, format="f", digits=1))
  ) |>
  select(ARM, `n`, `Mean (SD)`, `Median`, `Min, Max`) |>
  pivot_longer(-ARM, names_to = "rowlabel", values_to = "value") |>
  mutate(ord = 5, grouplabel = "Baseline BMI (kg/m2)",
         roworder = match(rowlabel, c("n","Mean (SD)","Median","Min, Max")))
# -- END BMIBL -- #

# -- BEGIN REPORT -- #
# Bind all display rows, pivot ARM to columns, render with gt
report_long <- bind_rows(d_AGE, d_AGEGR1, d_SEX, d_RACE, d_BMIBL) |>
  arrange(ord, roworder, ARM)

report_wide <- report_long |>
  pivot_wider(id_cols = c(ord, roworder, grouplabel, rowlabel),
              names_from = ARM, values_from = value) |>
  arrange(ord, roworder) |>
  select(-ord, -roworder)

demog_table <- report_wide |>
  gt(groupname_col = "grouplabel", rowname_col = "rowlabel") |>
  tab_header(title = "Table 14.1.1", subtitle = "Summary of Demographic and Baseline Characteristics") |>
  tab_source_note("N = number of subjects in the safety population.") |>
  tab_source_note("Percentages are based on N within each treatment group.")

demog_table
# -- END REPORT -- #
