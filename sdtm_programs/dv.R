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
# Program: dv.R
# Purpose: Create SDTM DV (Protocol Deviations) domain
# Domain:  DV (Events class - one row per event per subject)
# Inputs:  raw_dv, dm (both already in R session)
# Output:  dv
# ==============================================================================

library(dplyr)

# -- BEGIN DV -- #

# ==============================================================================
# Read source data (assumes raw_dv and dm are already loaded)
# ==============================================================================

# Note: raw_dv and dm are already available in the session

# ==============================================================================
# Derive USUBJID and merge RFSTDTC from DM
# ==============================================================================

# Extract required DM variables
dm_subset <- dm %>%
  select(STUDYID, USUBJID, RFSTDTC)

# Derive USUBJID if not already in raw_dv, otherwise use existing
# Assuming raw_dv has STUDYID, SITEID, SUBJID or already has USUBJID
dv_prep <- raw_dv %>%
  mutate(
    USUBJID = if ("USUBJID" %in% names(.)) {
      USUBJID
    } else {
      paste(STUDYID, SITEID, SUBJID, sep = "-")
    }
  )

# ==============================================================================
# Merge RFSTDTC from DM for study day calculations
# ==============================================================================

dv_prep <- dv_prep %>%
  left_join(dm_subset, by = c("STUDYID", "USUBJID"))

# ==============================================================================
# Assign DOMAIN
# ==============================================================================

dv_prep <- dv_prep %>%
  mutate(DOMAIN = "DV")

# ==============================================================================
# Map DV-specific variables from source
# Variable mappings (adjust based on actual raw_dv column names):
# - DVTERM: Reported term for the deviation
# - DVDECOD: Standardized/coded term for the deviation
# - DVCAT: Category (e.g., "PROTOCOL DEVIATION", "INCLUSION/EXCLUSION")
# - DVSCAT: Subcategory (e.g., specific deviation type)
# - DVBODSYS: Body system (typically not applicable for DV, set to NA)
# - DVSTDTC: Start date/time in ISO 8601 format
# - DVENDTC: End date/time in ISO 8601 format
# - EPOCH: Study epoch when deviation occurred
# ==============================================================================

dv_prep <- dv_prep %>%
  mutate(
    # Map reported term (verbatim)
    DVTERM = if ("DVTERM" %in% names(.)) {
      DVTERM
    } else if ("DV_VERBATIM" %in% names(.)) {
      DV_VERBATIM
    } else if ("DEVTERM" %in% names(.)) {
      DEVTERM
    } else {
      NA_character_
    },
    
    # Map dictionary-derived/coded term
    DVDECOD = if ("DVDECOD" %in% names(.)) {
      DVDECOD
    } else if ("DV_CODED" %in% names(.)) {
      DV_CODED
    } else if ("DEVDECOD" %in% names(.)) {
      DEVDECOD
    } else if ("DVTERM" %in% names(.) & !is.na(DVTERM)) {
      DVTERM
    } else {
      NA_character_
    },
    
    # Map category
    DVCAT = if ("DVCAT" %in% names(.)) {
      DVCAT
    } else if ("DV_CAT" %in% names(.)) {
      DV_CAT
    } else if ("CATEGORY" %in% names(.)) {
      CATEGORY
    } else {
      NA_character_
    },
    
    # Map subcategory
    DVSCAT = if ("DVSCAT" %in% names(.)) {
      DVSCAT
    } else if ("DV_SCAT" %in% names(.)) {
      DV_SCAT
    } else if ("SUBCATEGORY" %in% names(.)) {
      SUBCATEGORY
    } else {
      NA_character_
    },
    
    # Body system (typically not applicable for protocol deviations)
    DVBODSYS = if ("DVBODSYS" %in% names(.)) {
      DVBODSYS
    } else if ("BODSYS" %in% names(.)) {
      BODSYS
    } else {
      NA_character_
    },
    
    # Map start date/time (ISO 8601 format)
    DVSTDTC = if ("DVSTDTC" %in% names(.)) {
      DVSTDTC
    } else if ("DV_START_DTC" %in% names(.)) {
      DV_START_DTC
    } else if ("DVSTDAT" %in% names(.)) {
      as.character(DVSTDAT)
    } else if ("DEVSTDTC" %in% names(.)) {
      DEVSTDTC
    } else {
      NA_character_
    },
    
    # Map end date/time (ISO 8601 format)
    DVENDTC = if ("DVENDTC" %in% names(.)) {
      DVENDTC
    } else if ("DV_END_DTC" %in% names(.)) {
      DV_END_DTC
    } else if ("DVENDAT" %in% names(.)) {
      as.character(DVENDAT)
    } else if ("DEVENDTC" %in% names(.)) {
      DEVENDTC
    } else {
      NA_character_
    },
    
    # Map epoch
    EPOCH = if ("EPOCH" %in% names(.)) {
      EPOCH
    } else if ("DV_EPOCH" %in% names(.)) {
      DV_EPOCH
    } else {
      NA_character_
    }
  )

# ==============================================================================
# Derive study day variables (--STDY, --ENDY)
# Study day = (Event date - RFSTDTC) + 1 if event date >= RFSTDTC
#           = (Event date - RFSTDTC)     if event date < RFSTDTC
# ==============================================================================

dv_prep <- dv_prep %>%
  mutate(
    # Derive DVSTDY
    DVSTDY = case_when(
      is.na(DVSTDTC) | is.na(RFSTDTC) ~ NA_real_,
      DVSTDTC == "" | RFSTDTC == "" ~ NA_real_,
      TRUE ~ {
        dv_start_date <- as.Date(substr(DVSTDTC, 1, 10))
        rfst_date <- as.Date(substr(RFSTDTC, 1, 10))
        diff_days <- as.numeric(dv_start_date - rfst_date)
        if_else(diff_days >= 0, diff_days + 1, diff_days)
      }
    ),
    
    # Derive DVENDY
    DVENDY = case_when(
      is.na(DVENDTC) | is.na(RFSTDTC) ~ NA_real_,
      DVENDTC == "" | RFSTDTC == "" ~ NA_real_,
      TRUE ~ {
        dv_end_date <- as.Date(substr(DVENDTC, 1, 10))
        rfst_date <- as.Date(substr(RFSTDTC, 1, 10))
        diff_days <- as.numeric(dv_end_date - rfst_date)
        if_else(diff_days >= 0, diff_days + 1, diff_days)
      }
    )
  )

# ==============================================================================
# Derive EPOCH based on event date if not already mapped
# (Example logic - adjust based on study-specific epoch definitions)
# ==============================================================================

dv_prep <- dv_prep %>%
  mutate(
    EPOCH = case_when(
      !is.na(EPOCH) & EPOCH != "" ~ EPOCH,
      is.na(DVSTDTC) | DVSTDTC == "" ~ NA_character_,
      TRUE ~ {
        dv_date <- as.Date(substr(DVSTDTC, 1, 10))
        rfst_date <- as.Date(substr(RFSTDTC, 1, 10))
        case_when(
          is.na(rfst_date) ~ "SCREENING",
          dv_date < rfst_date ~ "SCREENING",
          TRUE ~ "TREATMENT"
        )
      }
    )
  )

# ==============================================================================
# Derive DVSEQ (sequence number within each subject)
# ==============================================================================

dv_prep <- dv_prep %>%
  group_by(STUDYID, USUBJID) %>%
  arrange(STUDYID, USUBJID, DVSTDTC) %>%
  mutate(DVSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# Sort by STUDYID, USUBJID, DVSEQ
# ==============================================================================

dv <- dv_prep %>%
  arrange(STUDYID, USUBJID, DVSEQ)

# ==============================================================================
# Select final variables in specification order
# ==============================================================================

dv <- dv %>%
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    DVSEQ,
    DVTERM,
    DVDECOD,
    DVCAT,
    DVSCAT,
    DVBODSYS,
    DVSTDTC,
    DVENDTC,
    DVSTDY,
    DVENDY,
    EPOCH
  )

# -- END DV -- #

# -- Verification -- #
# glimpse(dv)
# table(dv$DOMAIN)

# End of dv.R
