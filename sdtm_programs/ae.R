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
# Program:      AE Domain (Adverse Events)
# Purpose:      Generate SDTM AE domain from raw source data
# CDISC Model:  SDTM 3.x
# Domain:       AE (Events class - one row per event per subject)
# ==============================================================================

# -- BEGIN AE -- #

library(dplyr)

# ==============================================================================
# Derive AE domain
# ==============================================================================

ae <- raw_ae %>%
  
  # ----------------------------------------------------------------------------
  # Subject identifiers and reference dates
  # ----------------------------------------------------------------------------
  left_join(
    dm %>% select(STUDYID, SITEID, SUBJID, USUBJID, RFSTDTC, RFENDTC),
    by = c("STUDYID", "SITEID", "SUBJID")
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Basic domain setup
  # ----------------------------------------------------------------------------
  mutate(DOMAIN = "AE") %>%
  
  # ----------------------------------------------------------------------------
  # AE-specific variables from source
  # ----------------------------------------------------------------------------
  mutate(AETERM = AEVERBATIM) %>%
  mutate(AEDECOD = AECODED) %>%
  mutate(AEBODSYS = AESOC) %>%
  mutate(AECAT = CATEGORY) %>%
  mutate(AESCAT = if_else(!is.na(SUBCATEGORY), SUBCATEGORY, NA_character_)) %>%
  
  # ----------------------------------------------------------------------------
  # Date/time variables (ISO 8601 format)
  # ----------------------------------------------------------------------------
  mutate(AESTDTC = AESTDAT) %>%
  mutate(AEENDTC = AEENDAT) %>%
  
  # ----------------------------------------------------------------------------
  # Study day derivations
  # ----------------------------------------------------------------------------
  mutate(
    AESTDY = if_else(
      !is.na(AESTDTC) & !is.na(RFSTDTC),
      as.numeric(as.Date(substr(AESTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) +
        if_else(as.Date(substr(AESTDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1, 0),
      NA_real_
    )
  ) %>%
  
  mutate(
    AEENDY = if_else(
      !is.na(AEENDTC) & !is.na(RFSTDTC),
      as.numeric(as.Date(substr(AEENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) +
        if_else(as.Date(substr(AEENDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1, 0),
      NA_real_
    )
  ) %>%
  
  # ----------------------------------------------------------------------------
  # EPOCH derivation based on date relative to treatment period
  # ----------------------------------------------------------------------------
  mutate(
    EPOCH = case_when(
      is.na(AESTDTC) ~ NA_character_,
      !is.na(RFSTDTC) & as.Date(substr(AESTDTC, 1, 10)) < as.Date(substr(RFSTDTC, 1, 10)) ~ "SCREENING",
      !is.na(RFSTDTC) & !is.na(RFENDTC) & 
        as.Date(substr(AESTDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)) &
        as.Date(substr(AESTDTC, 1, 10)) <= as.Date(substr(RFENDTC, 1, 10)) ~ "TREATMENT",
      !is.na(RFENDTC) & as.Date(substr(AESTDTC, 1, 10)) > as.Date(substr(RFENDTC, 1, 10)) ~ "FOLLOW-UP",
      TRUE ~ "TREATMENT"
    )
  ) %>%
  
  # ----------------------------------------------------------------------------
  # AE-specific clinical variables
  # ----------------------------------------------------------------------------
  mutate(AEACN = ACTION) %>%
  mutate(AEOUT = OUTCOME) %>%
  mutate(AEREL = RELATED) %>%
  mutate(AESER = SERIOUS) %>%
  mutate(AESEV = SEVERITY) %>%
  
  # ----------------------------------------------------------------------------
  # Sequence number
  # ----------------------------------------------------------------------------
  group_by(USUBJID) %>%
  arrange(USUBJID, AESTDTC, AETERM) %>%
  mutate(AESEQ = row_number()) %>%
  ungroup() %>%
  
  # ----------------------------------------------------------------------------
  # Sort final dataset
  # ----------------------------------------------------------------------------
  arrange(STUDYID, USUBJID, AESEQ) %>%
  
  # ----------------------------------------------------------------------------
  # Select and order final variables per SDTM specification
  # ----------------------------------------------------------------------------
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

# ==============================================================================
# End of Program
# ==============================================================================


# -- BEGIN SUPPAE -- #

# Define qualifier variables metadata
qualifiers <- tribble(
  ~QNAM,       ~QLABEL,
  "AEACNOTH",  "Other Action Taken",
  "AESDTH",    "Led to Death?: Yes No",
  "AESHOSP",   "Led to Hospitalization?: Yes No",
  "AETRTEM",   "Treatment Emergent?: Yes No"
)

# Merge raw_ae with ae to get AESEQ
ae_base <- raw_ae %>%
  inner_join(
    ae %>% select(STUDYID, USUBJID, AESEQ),
    by = c("STUDYID", "USUBJID")
  )

# Pivot qualifier variables to long format
suppae <- ae_base %>%
  select(STUDYID, USUBJID, AESEQ, all_of(qualifiers$QNAM)) %>%
  pivot_longer(
    cols = all_of(qualifiers$QNAM),
    names_to = "QNAM",
    values_to = "QVAL",
    values_transform = as.character
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  left_join(qualifiers, by = "QNAM") %>%
  mutate(
    RDOMAIN = "AE",
    IDVAR = "AESEQ",
    IDVARVAL = as.character(AESEQ),
    QORIG = "CRF",
    QEVAL = NA_character_,
    AEACNOTH = if_else(QNAM == "AEACNOTH", QVAL, NA_character_),
    AESDTH = if_else(QNAM == "AESDTH", QVAL, NA_character_),
    AESHOSP = if_else(QNAM == "AESHOSP", QVAL, NA_character_),
    AETRTEM = if_else(QNAM == "AETRTEM", QVAL, NA_character_)
  ) %>%
  arrange(STUDYID, RDOMAIN, USUBJID, IDVARVAL, QNAM) %>%
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
    AEACNOTH,
    AESDTH,
    AESHOSP,
    AETRTEM
  )

# -- END SUPPAE -- #

# -- Verification -- #
# glimpse(ae)
# table(ae$DOMAIN)

# End of ae.R
