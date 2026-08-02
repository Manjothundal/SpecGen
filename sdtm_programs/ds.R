# ********************************************************************
# Program:    ds.R
# Domain:     DS (Events)
# Purpose:    Create SDTM DS domain data frame
# Variables:  14
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     ds data frame (DS domain dataset)
#
# Variables:  STUDYID, DSSEQ, USUBJID, DOMAIN, DSTERM, DSDECOD, DSCAT, DSSCAT
#             ...
# ********************************************************************

# ==============================================================================
# Program: ds.R
# Purpose: Create SDTM DS (Disposition) domain
# CDISC SDTM Version: 3.2
# ==============================================================================

library(dplyr)

# -- BEGIN DS -- #

# ==============================================================================
# Read source data
# Assumes raw_ds and dm are already loaded in the R session
# ==============================================================================

# ==============================================================================
# Derive USUBJID from dm and select RFSTDTC
# ==============================================================================

dm_subset <- dm %>%
  select(STUDYID, USUBJID, RFSTDTC)

# ==============================================================================
# Merge source disposition data with dm to get USUBJID and RFSTDTC
# ==============================================================================

ds <- raw_ds %>%
  left_join(dm_subset, by = c("STUDYID", "USUBJID")) %>%
  # Derive DOMAIN: Domain Abbreviation
  mutate(DOMAIN = "DS") %>%
  # Map DSTERM: Reported Term for the Event
  mutate(DSTERM = as.character(DSTERM)) %>%
  # Map DSDECOD: Dictionary-Derived Term
  mutate(DSDECOD = if_else(is.na(DSDECOD) | DSDECOD == "", DSTERM, as.character(DSDECOD))) %>%
  # Map DSCAT: Category for Event
  mutate(DSCAT = as.character(DSCAT)) %>%
  # Map DSSCAT: Subcategory for Event
  mutate(DSSCAT = if_else(is.na(DSSCAT) | DSSCAT == "", NA_character_, as.character(DSSCAT))) %>%
  # Map DSBODSYS: Body System or Organ Class (typically not applicable for DS)
  mutate(DSBODSYS = NA_character_) %>%
  # Map DSSTDTC: Start Date/Time of Event (ISO 8601 format)
  mutate(DSSTDTC = as.character(DSSTDTC)) %>%
  # Map DSENDTC: End Date/Time of Event (ISO 8601 format)
  mutate(DSENDTC = if_else(is.na(DSENDTC) | DSENDTC == "", NA_character_, as.character(DSENDTC))) %>%
  # Derive DSSTDY: Study Day of Start of Event
  mutate(
    DSSTDY = if_else(
      !is.na(DSSTDTC) & !is.na(RFSTDTC) & nchar(DSSTDTC) >= 10 & nchar(RFSTDTC) >= 10,
      as.numeric(as.Date(substr(DSSTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 
        if_else(as.Date(substr(DSSTDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1L, 0L),
      NA_real_
    )
  ) %>%
  # Derive DSENDY: Study Day of End of Event
  mutate(
    DSENDY = if_else(
      !is.na(DSENDTC) & !is.na(RFSTDTC) & nchar(DSENDTC) >= 10 & nchar(RFSTDTC) >= 10,
      as.numeric(as.Date(substr(DSENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 
        if_else(as.Date(substr(DSENDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1L, 0L),
      NA_real_
    )
  ) %>%
  # Map EPOCH: Epoch (from source or derive based on study design)
  mutate(EPOCH = as.character(EPOCH)) %>%
  # Derive DSSEQ: Sequence Number within subject
  group_by(USUBJID) %>%
  mutate(DSSEQ = row_number()) %>%
  ungroup() %>%
  # Sort by STUDYID, USUBJID, DSSEQ
  arrange(STUDYID, USUBJID, DSSEQ) %>%
  # Select final variables in specification order
  select(
    STUDYID,
    DSSEQ,
    USUBJID,
    DOMAIN,
    DSTERM,
    DSDECOD,
    DSCAT,
    DSSCAT,
    DSBODSYS,
    DSSTDTC,
    DSENDTC,
    DSSTDY,
    DSENDY,
    EPOCH
  )

# -- END DS -- #

# -- Verification -- #
# glimpse(ds)
# table(ds$DOMAIN)

# End of ds.R
