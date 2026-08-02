# ********************************************************************
# Program:    dv.R
# Domain:     DV (Events)
# Purpose:    Create SDTM DV domain data frame
# Variables:  14
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     dv data frame (DV domain dataset)
#
# Variables:  STUDYID, DVSEQ, USUBJID, DOMAIN, DVTERM, DVDECOD, DVCAT, DVSCAT
#             ...
# ********************************************************************

# ==============================================================================
# Program:      dv_sdtm.R
# Description:  Create SDTM DV (Protocol Deviations) domain
# SDTM Version: 3.2
# ==============================================================================

library(dplyr)

# -- BEGIN DV -- #

# ==============================================================================
# Read source data
# ==============================================================================
# Assumes raw_dv and dm are already loaded in the R session

# ==============================================================================
# Derive USUBJID if not present in raw_dv
# ==============================================================================
# Join dm to get USUBJID and RFSTDTC for study day calculations
dv <- raw_dv %>%
  left_join(
    dm %>% select(STUDYID, USUBJID, RFSTDTC),
    by = c("STUDYID", "USUBJID")
  )

# ==============================================================================
# Assign DOMAIN
# ==============================================================================
# Variable: DOMAIN (Domain Abbreviation)
dv <- dv %>%
  mutate(DOMAIN = "DV")

# ==============================================================================
# Map DV-specific variables from source
# ==============================================================================
# Variable: DVTERM (Reported Term for the Event)
# Variable: DVDECOD (Dictionary-Derived Term)
# Variable: DVCAT (Category for Event)
# Variable: DVSCAT (Subcategory for Event)
# Variable: DVBODSYS (Body System or Organ Class)
dv <- dv %>%
  mutate(
    DVTERM = if ("DVTERM_RAW" %in% names(.)) coalesce(DVTERM_RAW, DVTERM) else DVTERM,
    DVDECOD = if ("DVDECOD_RAW" %in% names(.)) coalesce(DVDECOD_RAW, DVDECOD, DVTERM) else coalesce(DVDECOD, DVTERM),
    DVCAT = if ("DVCAT_RAW" %in% names(.)) coalesce(DVCAT_RAW, DVCAT) else DVCAT,
    DVSCAT = if ("DVSCAT_RAW" %in% names(.)) coalesce(DVSCAT_RAW, DVSCAT) else DVSCAT,
    DVBODSYS = if ("DVBODSYS_RAW" %in% names(.)) coalesce(DVBODSYS_RAW, DVBODSYS) else DVBODSYS
  )

# ==============================================================================
# Map start and end dates
# ==============================================================================
# Variable: DVSTDTC (Start Date/Time of Event)
# Variable: DVENDTC (End Date/Time of Event)
dv <- dv %>%
  mutate(
    DVSTDTC = if ("DVSTDTC_RAW" %in% names(.)) coalesce(DVSTDTC_RAW, DVSTDTC) else DVSTDTC,
    DVENDTC = if ("DVENDTC_RAW" %in% names(.)) coalesce(DVENDTC_RAW, DVENDTC) else DVENDTC
  )

# ==============================================================================
# Derive study days
# ==============================================================================
# Variable: DVSTDY (Study Day of Start of Event)
# Variable: DVENDY (Study Day of End of Event)
# Study day calculation: if event date >= RFSTDTC then date - RFSTDTC + 1
#                        if event date < RFSTDTC then date - RFSTDTC
dv <- dv %>%
  mutate(
    DVSTDY = case_when(
      is.na(DVSTDTC) | is.na(RFSTDTC) ~ NA_real_,
      as.Date(substr(DVSTDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)) ~
        as.numeric(as.Date(substr(DVSTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 1,
      TRUE ~
        as.numeric(as.Date(substr(DVSTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10)))
    ),
    DVENDY = case_when(
      is.na(DVENDTC) | is.na(RFSTDTC) ~ NA_real_,
      as.Date(substr(DVENDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)) ~
        as.numeric(as.Date(substr(DVENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 1,
      TRUE ~
        as.numeric(as.Date(substr(DVENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10)))
    )
  )

# ==============================================================================
# Derive EPOCH based on date relative to treatment period
# ==============================================================================
# Variable: EPOCH (Epoch)
# This is a simplified derivation; adjust logic based on study-specific epochs
# Assumes EPOCH_RAW or EPOCH exists in raw_dv, or derive from dates
dv <- dv %>%
  mutate(
    EPOCH = case_when(
      "EPOCH_RAW" %in% names(.) & !is.na(EPOCH_RAW) ~ EPOCH_RAW,
      "EPOCH" %in% names(.) & !is.na(EPOCH) ~ EPOCH,
      !is.na(DVSTDY) & DVSTDY < 1 ~ "SCREENING",
      !is.na(DVSTDY) & DVSTDY >= 1 ~ "TREATMENT",
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# Derive DVSEQ
# ==============================================================================
# Variable: DVSEQ (Sequence Number)
# Sequence number within each subject
dv <- dv %>%
  group_by(USUBJID) %>%
  arrange(USUBJID, DVSTDTC) %>%
  mutate(DVSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# Sort dataset
# ==============================================================================
dv <- dv %>%
  arrange(STUDYID, USUBJID, DVSEQ)

# ==============================================================================
# Select and order final variables per SDTM specification
# ==============================================================================
# Keep only SDTM variables in specified order
dv <- dv %>%
  select(
    STUDYID,      # Study Identifier
    DVSEQ,        # Sequence Number
    USUBJID,      # Unique Subject Identifier
    DOMAIN,       # Domain Abbreviation
    DVTERM,       # Reported Term for the Event
    DVDECOD,      # Dictionary-Derived Term
    DVCAT,        # Category for Event
    DVSCAT,       # Subcategory for Event
    DVBODSYS,     # Body System or Organ Class
    DVSTDTC,      # Start Date/Time of Event
    DVENDTC,      # End Date/Time of Event
    DVSTDY,       # Study Day of Start of Event
    DVENDY,       # Study Day of End of Event
    EPOCH         # Epoch
  )

# -- END DV -- #

# -- Verification -- #
# glimpse(dv)
# table(dv$DOMAIN)

# End of dv.R
