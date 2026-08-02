# ********************************************************************
# Program:    dm.R
# Domain:     DM (DM)
# Purpose:    Create SDTM DM domain data frame
# Variables:  24
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     dm data frame (DM domain dataset)
#
# Variables:  STUDYID, DMSEQ, USUBJID, DOMAIN, RFSTDTC, RFENDTC, RFXSTDTC, RFXENDTC
#             ...
# ********************************************************************

# =============================================================================
# Program:       dm.R
# Description:   SDTM DM (Demographics) domain derivation
# =============================================================================

library(dplyr)

# =============================================================================
# 1. Start with raw_dm and derive SDTM variables
# =============================================================================

dm <- raw_dm %>%
  mutate(
    STUDYID = "STUDY123",
    DOMAIN = "DM",
    SUBJID = as.character(subject_id),
    SITEID = as.character(site_id),
    USUBJID = paste(STUDYID, as.character(site_id), as.character(subject_id), sep = "-"),
    BRTHDTC = as.character(birth_date),
    SEX = as.character(sex),
    RACE = as.character(race),
    ETHNIC = as.character(ethnicity),
    RFICDTC = as.character(consent_date),
    RANDNUM = as.character(randomization_number),
    COUNTRY = as.character(country_code),
    INVID = as.character(investigator_id),
    INVNAM = as.character(investigator_name),
    ARM = as.character(arm_description)
  )

# =============================================================================
# 2. Derive ARM codes from ARM descriptions
# =============================================================================

dm <- dm %>%
  mutate(
    ARMCD = case_when(
      toupper(ARM) %in% c("PLACEBO", "PLACEBO GROUP") ~ "PBO",
      toupper(ARM) %in% c("TREATMENT", "TREATMENT GROUP", "ACTIVE") ~ "TRT",
      toupper(ARM) %in% c("LOW DOSE", "LOW") ~ "LOW",
      toupper(ARM) %in% c("HIGH DOSE", "HIGH") ~ "HIGH",
      toupper(ARM) %in% c("SCREEN FAILURE") ~ "SCRNFAIL",
      toupper(ARM) %in% c("NOT ASSIGNED") ~ "NOTASSGN",
      !is.na(ARM) ~ "ARM",
      TRUE ~ NA_character_
    )
  )

# =============================================================================
# 3. Derive reference start/end dates from exposure (raw_ex)
# =============================================================================

ex_dates <- raw_ex %>%
  mutate(
    SITEID = as.character(site_id),
    SUBJID = as.character(subject_id),
    EXSTDTC = as.character(exposure_start_date),
    EXENDTC = as.character(exposure_end_date)
  ) %>%
  group_by(SITEID, SUBJID) %>%
  summarise(
    RFSTDTC = min(EXSTDTC, na.rm = TRUE),
    RFENDTC = max(EXENDTC, na.rm = TRUE),
    RFXSTDTC = min(EXSTDTC, na.rm = TRUE),
    RFXENDTC = max(EXENDTC, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    RFSTDTC = if_else(is.infinite(RFSTDTC), NA_character_, RFSTDTC),
    RFENDTC = if_else(is.infinite(RFENDTC), NA_character_, RFENDTC),
    RFXSTDTC = if_else(is.infinite(RFXSTDTC), NA_character_, RFXSTDTC),
    RFXENDTC = if_else(is.infinite(RFXENDTC), NA_character_, RFXENDTC)
  )

dm <- dm %>%
  left_join(ex_dates, by = c("SITEID", "SUBJID"))

# =============================================================================
# 4. Derive AGE from birth date and reference start date
# =============================================================================

dm <- dm %>%
  mutate(
    AGE = case_when(
      !is.na(BRTHDTC) & !is.na(RFSTDTC) ~ as.numeric(floor(
        as.numeric(difftime(
          as.Date(substr(RFSTDTC, 1, 10)),
          as.Date(substr(BRTHDTC, 1, 10)),
          units = "days"
        )) / 365.25
      )),
      TRUE ~ NA_real_
    )
  )

# =============================================================================
# 5. Derive actual arm variables (default to planned arm)
# =============================================================================

dm <- dm %>%
  mutate(
    ACTARMCD = ARMCD,
    ACTARM = ARM
  )

# =============================================================================
# 6. Assign sequence number and final sort
# =============================================================================

dm <- dm %>%
  arrange(STUDYID, USUBJID) %>%
  mutate(DMSEQ = row_number())

# =============================================================================
# 7. Select and order final variables per SDTM specification
# =============================================================================

dm <- dm %>%
  select(
    STUDYID,
    DMSEQ,
    USUBJID,
    DOMAIN,
    RFSTDTC,
    RFENDTC,
    RFXSTDTC,
    RFXENDTC,
    SITEID,
    INVID,
    INVNAM,
    COUNTRY,
    ARMCD,
    ARM,
    ACTARMCD,
    ACTARM,
    AGE,
    BRTHDTC,
    ETHNIC,
    RACE,
    RANDNUM,
    RFICDTC,
    SEX,
    SUBJID
  ) %>%
  arrange(STUDYID, USUBJID)


# -- BEGIN SUPPDM -- #

# Define qualifier metadata
qual_metadata <- tribble(
  ~QNAM,     ~QLABEL,
  "COMPLT",  "Completed Study?: Yes No",
  "DCSREAS", "Reason for Discontinuation",
  "EDUYRN",  "Years of Education"
)

# Merge raw_dm with dm to get DMSEQ
dm_with_seq <- raw_dm %>%
  left_join(
    dm %>% select(STUDYID, USUBJID, DMSEQ),
    by = c("STUDYID", "USUBJID")
  )

# Pivot longer to create QNAM/QVAL rows
suppdm <- dm_with_seq %>%
  select(STUDYID, USUBJID, DMSEQ, all_of(qual_metadata$QNAM)) %>%
  pivot_longer(
    cols = all_of(qual_metadata$QNAM),
    names_to = "QNAM",
    values_to = "QVAL",
    values_transform = list(QVAL = as.character)
  ) %>%
  left_join(qual_metadata, by = "QNAM") %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  mutate(
    RDOMAIN = "DM",
    IDVAR = "DMSEQ",
    IDVARVAL = as.character(DMSEQ),
    QORIG = "CRF",
    QEVAL = NA_character_
  ) %>%
  arrange(STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM) %>%
  select(
    STUDYID,
    RDOMAIN,
    USUBJID,
    IDVAR,
    IDVARVAL,
    QNAM,
    QLABEL,
    QVAL,
    QORIG,
    QEVAL
  )

# -- END SUPPDM -- #

# -- Verification -- #
# glimpse(dm)
# table(dm$DOMAIN)

# End of dm.R
