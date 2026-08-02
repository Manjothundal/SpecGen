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

library(dplyr)

# -- BEGIN DM -- #

# ============================================================================
# SDTM DM Domain Derivation
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Start with raw demographics data
# ----------------------------------------------------------------------------
dm <- raw_dm %>%
  mutate(
    # Assigned variables
    STUDYID = "STUDY123",                                    # Study Identifier
    DOMAIN = "DM",                                           # Domain Abbreviation
    
    # Derive Unique Subject Identifier
    USUBJID = paste(STUDYID, SITEID, SUBJID, sep = "-")     # Unique Subject Identifier
  )

# ----------------------------------------------------------------------------
# 2. Derive reference dates from exposure data (raw_ex)
# ----------------------------------------------------------------------------
# Calculate first and last exposure dates per subject
ex_dates <- raw_ex %>%
  mutate(USUBJID = paste("STUDY123", SITEID, SUBJID, sep = "-")) %>%
  group_by(USUBJID) %>%
  summarise(
    RFXSTDTC = min(EXSTDTC, na.rm = TRUE),                  # Date/Time of First Study Treatment
    RFXENDTC = max(EXENDTC, na.rm = TRUE),                  # Date/Time of Last Study Treatment
    .groups = "drop"
  ) %>%
  mutate(
    RFXSTDTC = if_else(is.infinite(RFXSTDTC), NA_character_, RFXSTDTC),
    RFXENDTC = if_else(is.infinite(RFXENDTC), NA_character_, RFXENDTC)
  )

# ----------------------------------------------------------------------------
# 3. Merge exposure dates back to DM
# ----------------------------------------------------------------------------
dm <- dm %>%
  left_join(ex_dates, by = "USUBJID") %>%
  mutate(
    # Reference Start/End Date = First/Last Study Treatment
    RFSTDTC = RFXSTDTC,                                      # Subject Reference Start Date/Time
    RFENDTC = RFXENDTC                                       # Subject Reference End Date/Time
  )

# ----------------------------------------------------------------------------
# 4. Derive AGE if not collected
# ----------------------------------------------------------------------------
dm <- dm %>%
  mutate(
    # Compute AGE from BRTHDTC and RFSTDTC if AGE is missing
    AGE = if_else(
      is.na(AGE) & !is.na(BRTHDTC) & !is.na(RFSTDTC),
      as.numeric(floor(
        (as.Date(substr(RFSTDTC, 1, 10)) - as.Date(substr(BRTHDTC, 1, 10))) / 365.25
      )),
      as.numeric(AGE)
    )
  )

# ----------------------------------------------------------------------------
# 5. Derive Actual ARM variables
# ----------------------------------------------------------------------------
# If actual arm not separately collected, set equal to planned arm
dm <- dm %>%
  mutate(
    ACTARMCD = if_else(is.na(ACTARMCD), ARMCD, ACTARMCD),    # Actual Arm Code
    ACTARM = if_else(is.na(ACTARM), ARM, ACTARM)             # Description of Actual Arm
  )

# ----------------------------------------------------------------------------
# 6. Assign sequence number
# ----------------------------------------------------------------------------
dm <- dm %>%
  arrange(STUDYID, USUBJID) %>%
  mutate(
    DMSEQ = row_number()                                     # Sequence Number
  )

# ----------------------------------------------------------------------------
# 7. Select and order final variables per SDTM specification
# ----------------------------------------------------------------------------
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

# -- END DM -- #


# -- BEGIN SUPPDM -- #

# Define qualifier variable metadata
qualifier_specs <- tribble(
  ~qnam,     ~qlabel,                           ~source_var,
  "COMPLT",  "Completed Study?: Yes No",        "COMPLT",
  "DCSREAS", "Reason for Discontinuation",      "DCSREAS",
  "EDUYRN",  "Years of Education",              "EDUYRN"
)

# Merge raw_dm with dm to get DMSEQ
dm_with_raw <- raw_dm %>%
  inner_join(
    dm %>% select(STUDYID, USUBJID, DMSEQ),
    by = c("STUDYID", "USUBJID")
  )

# Pivot qualifier variables to long format
suppdm <- dm_with_raw %>%
  select(STUDYID, USUBJID, DMSEQ, all_of(qualifier_specs$source_var)) %>%
  pivot_longer(
    cols = all_of(qualifier_specs$source_var),
    names_to = "QNAM",
    values_to = "QVAL",
    values_transform = as.character
  ) %>%
  left_join(
    qualifier_specs %>% select(qnam, qlabel),
    by = c("QNAM" = "qnam")
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  mutate(
    RDOMAIN = "DM",
    IDVAR = "DMSEQ",
    IDVARVAL = as.character(DMSEQ),
    QLABEL = qlabel,
    QORIG = "CRF",
    QEVAL = NA_character_
  ) %>%
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
  ) %>%
  arrange(STUDYID, RDOMAIN, USUBJID, IDVARVAL, QNAM)

# -- END SUPPDM -- #

# -- Verification -- #
# glimpse(dm)
# table(dm$DOMAIN)

# End of dm.R
