# ********************************************************************
# Program:    eg.R
# Domain:     EG (Findings)
# Purpose:    Create SDTM EG domain data frame
# Variables:  19
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     eg data frame (EG domain dataset)
#
# Variables:  STUDYID, EGSEQ, USUBJID, DOMAIN, EGTESTCD, EGTEST, EGCAT, EGORRES
#             ...
# ********************************************************************

# ==============================================================================
# Program: eg.R
# Purpose: Create SDTM EG domain (ECG findings) from raw data
# SDTM version: 3.2
# ==============================================================================

# Load required libraries
library(dplyr)
library(tidyr)

# -- BEGIN EG -- #

# ==============================================================================
# Variable labels (metadata - R does not enforce):
# STUDYID   : Study Identifier
# EGSEQ     : Sequence Number
# USUBJID   : Unique Subject Identifier
# DOMAIN    : Domain Abbreviation
# EGTESTCD  : Short Name of Measurement
# EGTEST    : Name of Measurement
# EGCAT     : Category for Findings
# EGORRES   : Result or Finding in Original Units
# EGORRESU  : Original Units
# EGSTRESC  : Character Result in Std Format
# EGSTRESN  : Numeric Result in Standard Units
# EGSTRESU  : Standard Units
# EGSTAT    : Completion Status
# EGREASND  : Reason Not Performed
# VISITNUM  : Visit Number
# VISIT     : Visit Name
# EGDTC     : Date/Time of Collection
# EGDY      : Study Day of Collection
# EGEVAL    : Overall Interpretation
# ==============================================================================

# ==============================================================================
# Step 1: Prepare Demographics data for derivations
# ==============================================================================

dm_subset <- dm %>%
  select(STUDYID, USUBJID, RFSTDTC)

# ==============================================================================
# Step 2: Transform raw EG data from wide to long format (if needed)
# ==============================================================================

# Check if raw_eg is in wide or vertical format
# Assuming wide format with columns like: STUDYID, SITEID, SUBJID, VISIT, VISITNUM,
# EGDTC, HR, QT, QTC, RR, PR, QRS, EGEVAL, EGREASND, etc.

# Define test parameter mappings
test_params <- tribble(
  ~test_col,  ~EGTESTCD, ~EGTEST,              ~EGORRESU,     ~EGSTRESU,
  "HR",       "HR",      "Heart Rate",         "beats/min",   "beats/min",
  "QT",       "QT",      "QT Duration",        "msec",        "msec",
  "QTC",      "QTCF",    "QTcF Duration",      "msec",        "msec",
  "RR",       "RR",      "RR Duration",        "msec",        "msec",
  "PR",       "PR",      "PR Duration",        "msec",        "msec",
  "QRS",      "QRS",     "QRS Duration",       "msec",        "msec"
)

# Pivot raw data from wide to long format
eg_long <- raw_eg %>%
  pivot_longer(
    cols = any_of(test_params$test_col),
    names_to = "test_col",
    values_to = "EGORRES_RAW",
    values_transform = list(EGORRES_RAW = as.character)
  ) %>%
  # Join test parameter mappings
  left_join(test_params, by = "test_col") %>%
  # Remove rows where test column was not present and no reason not done
  filter(!is.na(EGORRES_RAW) | !is.na(EGREASND))

# ==============================================================================
# Step 3: Derive core SDTM variables
# ==============================================================================

eg_core <- eg_long %>%
  # Derive USUBJID if not present
  mutate(
    USUBJID = if("USUBJID" %in% names(.)) USUBJID else paste(STUDYID, SITEID, SUBJID, sep = "-"),
    DOMAIN = "EG"
  ) %>%
  # Map original results and units
  mutate(
    EGORRES = as.character(EGORRES_RAW),
    EGCAT = "ECG"
  ) %>%
  # Derive standardized character result
  mutate(
    EGSTRESC = if_else(!is.na(EGORRES), as.character(EGORRES), NA_character_)
  ) %>%
  # Derive numeric result
  mutate(
    EGSTRESN = if_else(!is.na(EGORRES), suppressWarnings(as.numeric(EGORRES)), NA_real_)
  ) %>%
  # Derive completion status
  mutate(
    EGSTAT = if_else(is.na(EGORRES) & !is.na(EGREASND), "NOT DONE", NA_character_),
    EGREASND = if_else(!is.na(EGREASND), as.character(EGREASND), NA_character_)
  )

# ==============================================================================
# Step 4: Merge with DM to derive study day
# ==============================================================================

eg_with_dm <- eg_core %>%
  left_join(dm_subset, by = c("STUDYID", "USUBJID")) %>%
  # Derive study day (EGDY)
  mutate(
    EGDY = if_else(
      !is.na(EGDTC) & !is.na(RFSTDTC) & EGDTC != "" & RFSTDTC != "",
      as.numeric(as.Date(substr(EGDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) +
        if_else(as.Date(substr(EGDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1L, 0L),
      NA_real_
    )
  )

# ==============================================================================
# Step 5: Derive sequence number
# ==============================================================================

eg_with_seq <- eg_with_dm %>%
  arrange(STUDYID, USUBJID, EGTESTCD, VISITNUM, EGDTC) %>%
  group_by(USUBJID) %>%
  mutate(EGSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# Step 6: Select and order final variables per specification
# ==============================================================================

eg <- eg_with_seq %>%
  select(
    STUDYID,
    EGSEQ,
    USUBJID,
    DOMAIN,
    EGTESTCD,
    EGTEST,
    EGCAT,
    EGORRES,
    EGORRESU,
    EGSTRESC,
    EGSTRESN,
    EGSTRESU,
    EGSTAT,
    EGREASND,
    VISITNUM,
    VISIT,
    EGDTC,
    EGDY,
    EGEVAL
  ) %>%
  # Final sort
  arrange(STUDYID, USUBJID, EGSEQ)

# -- END EG -- #

# ==============================================================================
# End of program
# ==============================================================================

# -- BEGIN SUPPEG -- #

# Merge EG and raw_eg to get both EGSEQ and qualifier variables
suppeg_source <- eg %>%
  select(STUDYID, USUBJID, EGSEQ) %>%
  left_join(
    raw_eg %>% select(STUDYID, USUBJID, any_of(c("EGCLSIG"))),
    by = c("STUDYID", "USUBJID")
  )

# Define qualifier metadata
qualifier_metadata <- tribble(
  ~QNAM,      ~QLABEL,                              ~QORIG, ~QEVAL,
  "EGCLSIG",  "Clinically Significant?: Yes No",    "CRF",  NA_character_
)

# Transpose qualifier variables to long format
suppeg <- suppeg_source %>%
  pivot_longer(
    cols = all_of(qualifier_metadata$QNAM),
    names_to = "QNAM",
    values_to = "QVAL"
  ) %>%
  filter(!is.na(QVAL)) %>%
  left_join(qualifier_metadata, by = "QNAM") %>%
  mutate(
    RDOMAIN = "EG",
    IDVAR = "EGSEQ",
    IDVARVAL = as.character(EGSEQ),
    QVAL = as.character(QVAL)
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
    QEVAL,
    EGCLSIG
  )

# -- END SUPPEG -- #

# -- Verification -- #
# glimpse(eg)
# table(eg$DOMAIN)

# End of eg.R
