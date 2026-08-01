library(dplyr)

library(tidyr)



# -- BEGIN TABLE_SETUP -- #
# Table 14.1.1 — Summary of Demographic and Baseline Characteristics
# Population: keep only SAFFL == "Y"
tab <- adsl |>
  filter(SAFFL == "Y")
# -- END TABLE_SETUP -- #

# -- BEGIN AGE -- #
# Age (years) — continuous summary by TRT01A
c_AGE <- tab |>
  group_by(TRT01A) |>
  summarise(
    n = sum(!is.na(AGE)),
    mean = mean(AGE, na.rm = TRUE),
    sd = sd(AGE, na.rm = TRUE),
    median = median(AGE, na.rm = TRUE),
    min = min(AGE, na.rm = TRUE),
    max = max(AGE, na.rm = TRUE),
    .groups = "drop"
  )
# -- END AGE -- #

# -- BEGIN AGEGR1 -- #
# Age Group, n (%) — categorical n (%) by TRT01A
f_AGEGR1 <- tab |>
  group_by(TRT01A, AGEGR1) |>
  summarise(n = n(), .groups = "drop") |>
  group_by(TRT01A) |>
  mutate(pct = 100 * n / sum(n)) |>
  ungroup()
# -- END AGEGR1 -- #

# -- BEGIN SEX -- #
# Sex, n (%) — categorical n (%) by TRT01A
f_SEX <- tab |>
  group_by(TRT01A, SEX) |>
  summarise(n = n(), .groups = "drop") |>
  group_by(TRT01A) |>
  mutate(pct = 100 * n / sum(n)) |>
  ungroup()
# -- END SEX -- #

# -- BEGIN RACE -- #
# Race, n (%) — categorical n (%) by TRT01A
f_RACE <- tab |>
  group_by(TRT01A, RACE) |>
  summarise(n = n(), .groups = "drop") |>
  group_by(TRT01A) |>
  mutate(pct = 100 * n / sum(n)) |>
  ungroup()
# -- END RACE -- #

# -- BEGIN BMIBL -- #
# Baseline BMI (kg/m2) — continuous summary by TRT01A
c_BMIBL <- tab |>
  group_by(TRT01A) |>
  summarise(
    n = sum(!is.na(BMIBL)),
    mean = mean(BMIBL, na.rm = TRUE),
    sd = sd(BMIBL, na.rm = TRUE),
    median = median(BMIBL, na.rm = TRUE),
    min = min(BMIBL, na.rm = TRUE),
    max = max(BMIBL, na.rm = TRUE),
    .groups = "drop"
  )
# -- END BMIBL -- #

# -- BEGIN REPORT -- #
# TODO: bind the per-variable summaries in display order, pivot to one column
# per TRT01A (+ Total), render with gt::gt() and the shell footnotes.
# -- END REPORT -- #
