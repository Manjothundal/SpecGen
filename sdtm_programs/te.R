# ********************************************************************
# Program:    te.R
# Domain:     TE (General)
# Purpose:    Create SDTM TE domain data frame
# Variables:  7
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     te data frame (TE domain dataset)
#
# Variables:  STUDYID, DOMAIN, ETCD, ELEMENT, TESTRL, TEENRL, TEDUR
#             
# ********************************************************************

# ==============================================================================
# Program: te.R
# Purpose: Create SDTM TE (Trial Elements) domain
# SDTM Version: 3.2
# ==============================================================================

library(dplyr)

# -- BEGIN TE -- #

# ==============================================================================
# Read source data
# Note: raw_te is already loaded in the R session
# ==============================================================================

# ==============================================================================
# Create TE domain
# TE is a trial-level dataset describing protocol elements
# No USUBJID required - this is study design metadata
# ==============================================================================

te <- raw_te %>%
  
  # ==============================================================================
  # Assign DOMAIN
  # ==============================================================================
  mutate(
    DOMAIN = "TE"  # Domain Abbreviation
  ) %>%
  
  # ==============================================================================
  # Map protocol-specified trial elements
  # ETCD: Element Code
  # ELEMENT: Description of Element
  # TESTRL: Rule for Start of Element
  # TEENRL: Rule for End of Element
  # TEDUR: Planned Duration of Element
  # ==============================================================================
  mutate(
    STUDYID = if ("STUDYID" %in% names(.)) STUDYID else NA_character_,
    ETCD = case_when(
      "ETCD" %in% names(.) & !is.na(ETCD) ~ ETCD,
      "ELEMENT_CODE" %in% names(.) & !is.na(ELEMENT_CODE) ~ ELEMENT_CODE,
      TRUE ~ NA_character_
    ),
    ELEMENT = case_when(
      "ELEMENT" %in% names(.) & !is.na(ELEMENT) ~ ELEMENT,
      "ELEMENT_DESC" %in% names(.) & !is.na(ELEMENT_DESC) ~ ELEMENT_DESC,
      "ELEMENT_NAME" %in% names(.) & !is.na(ELEMENT_NAME) ~ ELEMENT_NAME,
      TRUE ~ NA_character_
    ),
    TESTRL = case_when(
      "TESTRL" %in% names(.) & !is.na(TESTRL) ~ TESTRL,
      "START_RULE" %in% names(.) & !is.na(START_RULE) ~ START_RULE,
      TRUE ~ NA_character_
    ),
    TEENRL = case_when(
      "TEENRL" %in% names(.) & !is.na(TEENRL) ~ TEENRL,
      "END_RULE" %in% names(.) & !is.na(END_RULE) ~ END_RULE,
      TRUE ~ NA_character_
    ),
    TEDUR = case_when(
      "TEDUR" %in% names(.) & !is.na(TEDUR) ~ TEDUR,
      "DURATION" %in% names(.) & !is.na(DURATION) ~ DURATION,
      "PLANNED_DURATION" %in% names(.) & !is.na(PLANNED_DURATION) ~ PLANNED_DURATION,
      TRUE ~ NA_character_
    )
  ) %>%
  
  # ==============================================================================
  # Select only SDTM TE domain variables in specification order
  # Variable specifications (labels noted in comments):
  # STUDYID - Study Identifier
  # DOMAIN - Domain Abbreviation
  # ETCD - Element Code
  # ELEMENT - Description of Element
  # TESTRL - Rule for Start of Element
  # TEENRL - Rule for End of Element
  # TEDUR - Planned Duration of Element
  # ==============================================================================
  select(
    STUDYID,    # Study Identifier
    DOMAIN,     # Domain Abbreviation
    ETCD,       # Element Code
    ELEMENT,    # Description of Element
    TESTRL,     # Rule for Start of Element
    TEENRL,     # Rule for End of Element
    TEDUR       # Planned Duration of Element
  ) %>%
  
  # ==============================================================================
  # Sort final dataset
  # TE is a trial-level dataset describing protocol elements
  # Sorting by STUDYID and ETCD for consistent ordering
  # ==============================================================================
  arrange(
    STUDYID,
    ETCD
  )

# -- END TE -- #

# ==============================================================================
# End of Program
# ==============================================================================

# -- Verification -- #
# glimpse(te)
# table(te$DOMAIN)

# End of te.R
