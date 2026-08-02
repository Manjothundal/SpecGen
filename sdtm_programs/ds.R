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
# Program:      DS domain creation
# Description:  Disposition Events domain for SDTM
# Input:        raw_ds, dm (already in R session)
# Output:       ds
# CDISC Class:  Events (one record per disposition event per subject)
# ==============================================================================

# -- BEGIN DS -- #

library(dplyr)

# ------------------------------------------------------------------------------
# Read source data (already in session)
# ------------------------------------------------------------------------------
# raw_ds: source disposition data
# dm:     demographics domain (for USUBJID, RFSTDTC)

# ------------------------------------------------------------------------------
# Derive study day function
# ------------------------------------------------------------------------------
# Calculate study day relative to reference start date
# Study day = date - RFSTDTC + 1 if date >= RFSTDTC
#           = date - RFSTDTC     if date < RFSTDTC
derive_study_day <- function(dtc, rfstdtc) {
  if (is.na(dtc) || is.na(rfstdtc) || dtc == "" || rfstdtc == "") {
    return(NA_integer_)
  }
  
  dt <- as.Date(substr(dtc, 1, 10))
  rfstdt <- as.Date(substr(rfstdtc, 1, 10))
  
  if (is.na(dt) || is.na(rfstdt)) {
    return(NA_integer_)
  }
  
  diff <- as.integer(dt - rfstdt)
  if (diff >= 0) {
    return(diff + 1L)
  } else {
    return(diff)
  }
}

# ------------------------------------------------------------------------------
# Derive EPOCH based on date relative to treatment periods
# ------------------------------------------------------------------------------
# Simple example: assign EPOCH based on disposition event timing
# In production, this would reference trial design dates from TA/TE/TV domains
derive_epoch <- function(dsstdtc, rfstdtc, rfendtc) {
  if (is.na(dsstdtc) || dsstdtc == "") {
    return(NA_character_)
  }
  
  dsdt <- as.Date(substr(dsstdtc, 1, 10))
  
  if (is.na(dsdt)) {
    return(NA_character_)
  }
  
  # If before reference start date
  if (!is.na(rfstdtc) && rfstdtc != "") {
    rfstdt <- as.Date(substr(rfstdtc, 1, 10))
    if (!is.na(rfstdt) && dsdt < rfstdt) {
      return("SCREENING")
    }
  }
  
  # If after reference end date
  if (!is.na(rfendtc) && rfendtc != "") {
    rfendt <- as.Date(substr(rfendtc, 1, 10))
    if (!is.na(rfendt) && dsdt > rfendt) {
      return("FOLLOW-UP")
    }
  }
  
  # Otherwise treatment period
  return("TREATMENT")
}

# ------------------------------------------------------------------------------
# Build DS domain
# ------------------------------------------------------------------------------

ds <- raw_ds %>%
  # Join with DM to get USUBJID and reference dates
  left_join(
    dm %>% select(STUDYID, USUBJID, RFSTDTC, RFENDTC),
    by = c("STUDYID", "USUBJID")
  ) %>%
  
  # Map core variables
  mutate(
    # Domain abbreviation (Assigned)
    DOMAIN = "DS",
    
    # Reported Term for the Disposition Event (CRF)
    DSTERM = as.character(DSTERM),
    
    # Standardized/Dictionary-Derived Term (CRF)
    DSDECOD = if_else(is.na(DSDECOD) | DSDECOD == "", DSTERM, as.character(DSDECOD)),
    
    # Category for Disposition Event (CRF)
    # e.g., "PROTOCOL MILESTONE", "DISPOSITION EVENT"
    DSCAT = as.character(DSCAT),
    
    # Subcategory for Disposition Event (CRF)
    DSSCAT = as.character(DSSCAT),
    
    # Body System or Organ Class (Derived)
    # Generally not applicable for DS; left as NA or empty
    DSBODSYS = NA_character_,
    
    # Start Date/Time of Disposition Event (CRF)
    # Ensure ISO 8601 format
    DSSTDTC = as.character(DSSTDTC),
    
    # End Date/Time of Disposition Event (CRF)
    # Usually not applicable for DS
    DSENDTC = as.character(DSENDTC)
  ) %>%
  
  # Derive study days
  rowwise() %>%
  mutate(
    # Study Day of Start of Disposition Event (Derived)
    DSSTDY = derive_study_day(DSSTDTC, RFSTDTC),
    
    # Study Day of End of Disposition Event (Derived)
    DSENDY = derive_study_day(DSENDTC, RFSTDTC),
    
    # Epoch (Derived from date/protocol milestone)
    EPOCH = derive_epoch(DSSTDTC, RFSTDTC, RFENDTC)
  ) %>%
  ungroup() %>%
  
  # Derive sequence number within subject
  group_by(USUBJID) %>%
  arrange(USUBJID, DSSTDTC, DSTERM) %>%
  mutate(
    # Sequence Number (Derived)
    DSSEQ = row_number()
  ) %>%
  ungroup() %>%
  
  # Final sort order
  arrange(STUDYID, USUBJID, DSSEQ) %>%
  
  # Select and order variables per SDTM specification
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

# ==============================================================================
# End of script
# ==============================================================================

# -- Verification -- #
# glimpse(ds)
# table(ds$DOMAIN)

# End of ds.R
