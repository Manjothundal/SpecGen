# ********************************************************************
# Program:    ae.R
# Domain:     AE (Events)
# Purpose:    Create SDTM AE domain data frame
# Variables:  19
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     ae data frame (AE domain dataset)
#
# Variables:  STUDYID, AESEQ, USUBJID, DOMAIN, AETERM, AEDECOD, AECAT, AESCAT
#             ...
# ********************************************************************

# ==============================================================================
# Program:      ae.R
# Description:  SDTM AE (Adverse Events) Domain
# CDISC SDTM:   Events Class - one row per event per subject
# ==============================================================================

library(dplyr)

# -- BEGIN AE -- #

# ==============================================================================
# Variable Labels (for reference - not applied in R)
# ==============================================================================
# STUDYID   : Study Identifier
# AESEQ     : Sequence Number
# USUBJID   : Unique Subject Identifier
# DOMAIN    : Domain Abbreviation
# AETERM    : Reported Term for the Event
# AEDECOD   : Dictionary-Derived Term
# AECAT     : Category for Event
# AESCAT    : Subcategory for Event
# AEBODSYS  : Body System or Organ Class
# AESTDTC   : Start Date/Time of Event
# AEENDTC   : End Date/Time of Event
# AESTDY    : Study Day of Start of Event
# AEENDY    : Study Day of End of Event
# EPOCH     : Epoch
# AEACN     : Action Taken with Study Treatment
# AEOUT     : Outcome of Adverse Event
# AEREL     : Causality
# AESER     : Serious Event
# AESEV     : Severity/Intensity
# ==============================================================================

# ==============================================================================
# Derive AE domain
# ==============================================================================

ae <- raw_ae %>%
  
  # ============================================================================
  # Merge DM to get subject-level variables
  # ============================================================================
  left_join(
    dm %>% select(STUDYID, USUBJID, RFSTDTC),
    by = c("STUDYID", "USUBJID")
  ) %>%
  
  # ============================================================================
  # Assign Domain
  # ============================================================================
  mutate(DOMAIN = "AE") %>%
  
  # ============================================================================
  # Map source variables to SDTM variables
  # ============================================================================
  mutate(
    # Map Reported Term
    AETERM = AETERM_RAW,
    
    # Map Dictionary-Derived Term
    AEDECOD = AEDECOD_RAW,
    
    # Map Body System or Organ Class
    AEBODSYS = AEBODSYS_RAW,
    
    # Map Category
    AECAT = AECAT_RAW,
    
    # Map Subcategory
    AESCAT = AESCAT_RAW,
    
    # Map Start Date/Time (ISO 8601)
    AESTDTC = AESTDTC_RAW,
    
    # Map End Date/Time (ISO 8601)
    AEENDTC = AEENDTC_RAW,
    
    # Map Action Taken
    AEACN = AEACN_RAW,
    
    # Map Outcome
    AEOUT = AEOUT_RAW,
    
    # Map Causality
    AEREL = AEREL_RAW,
    
    # Map Serious Event
    AESER = AESER_RAW,
    
    # Map Severity
    AESEV = AESEV_RAW
  ) %>%
  
  # ============================================================================
  # Derive Study Day variables
  # ============================================================================
  mutate(
    # Parse reference start date
    RFSTDT = as.Date(substr(RFSTDTC, 1, 10)),
    
    # Parse AE start date
    AESTDT = as.Date(substr(AESTDTC, 1, 10)),
    
    # Parse AE end date
    AEENDT = as.Date(substr(AEENDTC, 1, 10)),
    
    # Derive Study Day of Start
    AESTDY = if_else(
      !is.na(AESTDT) & !is.na(RFSTDT),
      as.numeric(AESTDT - RFSTDT) + if_else(AESTDT >= RFSTDT, 1L, 0L),
      NA_real_
    ),
    
    # Derive Study Day of End
    AEENDY = if_else(
      !is.na(AEENDT) & !is.na(RFSTDT),
      as.numeric(AEENDT - RFSTDT) + if_else(AEENDT >= RFSTDT, 1L, 0L),
      NA_real_
    )
  ) %>%
  
  # ============================================================================
  # Derive EPOCH based on date relative to treatment period
  # ============================================================================
  mutate(
    EPOCH = case_when(
      is.na(AESTDT) ~ NA_character_,
      !is.na(AESTDY) & AESTDY < 1 ~ "SCREENING",
      !is.na(AESTDY) & AESTDY >= 1 ~ "TREATMENT",
      TRUE ~ NA_character_
    )
  ) %>%
  
  # ============================================================================
  # Derive AESEQ - Sequence Number within subject
  # ============================================================================
  group_by(USUBJID) %>%
  arrange(USUBJID, AESTDTC, AETERM) %>%
  mutate(AESEQ = row_number()) %>%
  ungroup() %>%
  
  # ============================================================================
  # Sort final dataset
  # ============================================================================
  arrange(STUDYID, USUBJID, AESEQ) %>%
  
  # ============================================================================
  # Select final variables in specification order
  # ============================================================================
  select(
    STUDYID,
    AESEQ,
    USUBJID,
    DOMAIN,
    AETERM,
    AEDECOD,
    AECAT,
    AESCAT,
    AEBODSYS,
    AESTDTC,
    AEENDTC,
    AESTDY,
    AEENDY,
    EPOCH,
    AEACN,
    AEOUT,
    AEREL,
    AESER,
    AESEV
  )

# -- END AE -- #


# -- BEGIN SUPPAE -- #


# Prepare qualifier metadata
qualifier_metadata <- tribble(
  ~QNAM,       ~QLABEL,
  "AEACNOTH",  "Other Action Taken",
  "AESDTH",    "Results in Death",
  "AESHOSP",   "Requires or Prolongs Hospitalization",
  "AETRTEM",   "Treatment Emergent Flag"
)

# Merge raw_ae with ae to get AESEQ
ae_with_qualifiers <- raw_ae %>%
  inner_join(
    ae %>% select(STUDYID, USUBJID, AESTDTC, AETERM, AESEQ),
    by = c("STUDYID", "USUBJID", "AESTDTC", "AETERM")
  ) %>%
  select(STUDYID, USUBJID, AESEQ, AEACNOTH, AESDTH, AESHOSP, AETRTEM)

# Pivot qualifiers to long format
suppae <- ae_with_qualifiers %>%
  pivot_longer(
    cols = c(AEACNOTH, AESDTH, AESHOSP, AETRTEM),
    names_to = "QNAM",
    values_to = "QVAL"
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  left_join(qualifier_metadata, by = "QNAM") %>%
  mutate(
    RDOMAIN = "AE",
    IDVAR = "AESEQ",
    IDVARVAL = as.character(AESEQ),
    QVAL = as.character(QVAL),
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
  arrange(STUDYID, USUBJID, IDVAR, IDVARVAL, QNAM)

# -- END SUPPAE -- #

# -- Verification -- #
# glimpse(ae)
# table(ae$DOMAIN)

# End of ae.R
