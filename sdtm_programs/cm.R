# ********************************************************************
# Program:    cm.R
# Domain:     CM (Interventions)
# Purpose:    Create SDTM CM domain data frame
# Variables:  19
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     cm data frame (CM domain dataset)
#
# Variables:  STUDYID, CMSEQ, USUBJID, DOMAIN, CMTRT, CMDECOD, CMCAT, CMDOSE
#             ...
# ********************************************************************

# ==============================================================================
# Program: CM Domain Derivation
# Purpose: Create SDTM CM (Concomitant Medications) domain
# Inputs:  raw_cm, dm
# Output:  cm
# ==============================================================================

library(dplyr)

# -- BEGIN CM --

# ==============================================================================
# Read source data (assumed to be already loaded in session)
# raw_cm: Source concomitant medications data
# dm: Demographics domain for USUBJID and reference dates
# ==============================================================================

# ==============================================================================
# Derive USUBJID and merge reference dates from DM
# ==============================================================================
cm <- raw_cm %>%
  left_join(
    dm %>% select(STUDYID, USUBJID, RFSTDTC, RFXSTDTC, RFXENDTC),
    by = c("STUDYID", "USUBJID"),
    relationship = "many-to-one"
  ) %>%
  mutate(
    # Domain Abbreviation
    DOMAIN = "CM",
    
    # Reported Name of Treatment
    CMTRT = CMTRT,
    
    # Standardized Treatment Name
    CMDECOD = if_else(!is.na(CMDECOD), CMDECOD, CMTRT),
    
    # Category for Intervention
    CMCAT = CMCAT,
    
    # Dose per Administration
    CMDOSE = as.numeric(CMDOSE),
    
    # Dose Units
    CMDOSU = CMDOSU,
    
    # Dosing Frequency per Interval
    CMDOSFRQ = CMDOSFRQ,
    
    # Route of Administration
    CMROUTE = CMROUTE,
    
    # Start Date/Time of Intervention (ISO 8601)
    CMSTDTC = CMSTDTC,
    
    # End Date/Time of Intervention (ISO 8601)
    CMENDTC = CMENDTC,
    
    # ATC Class
    CMCLAS = CMCLAS,
    
    # Indication
    CMINDC = CMINDC,
    
    # Ongoing at Screening
    CMONGO = CMONGO
  )

# ==============================================================================
# Derive study days (--STDY, --ENDY) relative to RFSTDTC
# Study Day = (Date - RFSTDTC) + 1 if Date >= RFSTDTC
#           = (Date - RFSTDTC) if Date < RFSTDTC
# ==============================================================================
cm <- cm %>%
  mutate(
    # Parse reference start date
    RFSTDTC_date = as.Date(substr(RFSTDTC, 1, 10)),
    
    # Parse CM start date
    CMSTDTC_date = if_else(
      !is.na(CMSTDTC) & nchar(CMSTDTC) >= 10,
      as.Date(substr(CMSTDTC, 1, 10)),
      as.Date(NA_character_)
    ),
    
    # Parse CM end date
    CMENDTC_date = if_else(
      !is.na(CMENDTC) & nchar(CMENDTC) >= 10,
      as.Date(substr(CMENDTC, 1, 10)),
      as.Date(NA_character_)
    ),
    
    # Study Day of Start of Intervention
    CMSTDY = case_when(
      is.na(CMSTDTC_date) | is.na(RFSTDTC_date) ~ NA_real_,
      CMSTDTC_date >= RFSTDTC_date ~ as.numeric(CMSTDTC_date - RFSTDTC_date) + 1,
      TRUE ~ as.numeric(CMSTDTC_date - RFSTDTC_date)
    ),
    
    # Study Day of End of Intervention
    CMENDY = case_when(
      is.na(CMENDTC_date) | is.na(RFSTDTC_date) ~ NA_real_,
      CMENDTC_date >= RFSTDTC_date ~ as.numeric(CMENDTC_date - RFSTDTC_date) + 1,
      TRUE ~ as.numeric(CMENDTC_date - RFSTDTC_date)
    )
  )

# ==============================================================================
# Derive EPOCH based on timing relative to treatment period
# ==============================================================================
cm <- cm %>%
  mutate(
    RFXSTDTC_date = if_else(
      !is.na(RFXSTDTC) & nchar(RFXSTDTC) >= 10,
      as.Date(substr(RFXSTDTC, 1, 10)),
      as.Date(NA_character_)
    ),
    RFXENDTC_date = if_else(
      !is.na(RFXENDTC) & nchar(RFXENDTC) >= 10,
      as.Date(substr(RFXENDTC, 1, 10)),
      as.Date(NA_character_)
    ),
    
    # Epoch derivation
    EPOCH = case_when(
      is.na(CMSTDTC_date) ~ NA_character_,
      !is.na(RFXSTDTC_date) & CMSTDTC_date < RFXSTDTC_date ~ "SCREENING",
      !is.na(RFXSTDTC_date) & !is.na(RFXENDTC_date) & 
        CMSTDTC_date >= RFXSTDTC_date & CMSTDTC_date <= RFXENDTC_date ~ "TREATMENT",
      !is.na(RFXENDTC_date) & CMSTDTC_date > RFXENDTC_date ~ "FOLLOW-UP",
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# Derive CMSEQ as sequence number within each subject
# ==============================================================================
cm <- cm %>%
  arrange(STUDYID, USUBJID, CMSTDTC, CMTRT) %>%
  group_by(USUBJID) %>%
  mutate(CMSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# Sort by STUDYID, USUBJID, CMSEQ
# ==============================================================================
cm <- cm %>%
  arrange(STUDYID, USUBJID, CMSEQ)

# ==============================================================================
# Select and order final variables per specification
# ==============================================================================
cm <- cm %>%
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    CMSEQ,
    CMTRT,
    CMDECOD,
    CMCAT,
    CMDOSE,
    CMDOSU,
    CMDOSFRQ,
    CMROUTE,
    CMSTDTC,
    CMENDTC,
    CMSTDY,
    CMENDY,
    EPOCH,
    CMCLAS,
    CMINDC,
    CMONGO
  )

# -- END CM --

# -- BEGIN SUPPCM -- #

# Define qualifier variable metadata
qual_vars <- tribble(
  ~QNAM,       ~QLABEL,
  "CMINDOTH",  "Other Indication",
  "CMPREVFL",  "Prior Medication"
)

# Merge raw_cm with cm to get CMSEQ
cm_with_qual <- raw_cm %>%
  inner_join(
    cm %>% select(STUDYID, USUBJID, CMTRT, CMSTDTC, CMSEQ),
    by = c("STUDYID", "USUBJID", "CMTRT", "CMSTDTC")
  )

# Create SUPPCM by pivoting qualifier variables to QNAM/QVAL
suppcm <- cm_with_qual %>%
  select(STUDYID, USUBJID, CMSEQ, all_of(qual_vars$QNAM)) %>%
  pivot_longer(
    cols = all_of(qual_vars$QNAM),
    names_to = "QNAM",
    values_to = "QVAL"
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  left_join(qual_vars, by = "QNAM") %>%
  mutate(
    RDOMAIN = "CM",
    IDVAR = "CMSEQ",
    IDVARVAL = as.character(CMSEQ),
    QVAL = as.character(QVAL),
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

# -- END SUPPCM -- #

# -- Verification -- #
# glimpse(cm)
# table(cm$DOMAIN)

# End of cm.R
