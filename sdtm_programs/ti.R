# ********************************************************************
# Program:    ti.R
# Domain:     TI (General)
# Purpose:    Create SDTM TI domain data frame
# Variables:  8
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     ti data frame (TI domain dataset)
#
# Variables:  STUDYID, DOMAIN, IETESTCD, IETEST  , IECAT, IESCAT, TIRL, TIVERS
#             
# ********************************************************************

# ==============================================================================
# Program: ti.R
# Purpose: Create SDTM TI (Trial Inclusion/Exclusion) domain
# SDTM Version: 3.x
# ==============================================================================

library(dplyr)

# -- BEGIN TI -- #

# ==============================================================================
# Read source data
# Assume raw_ti is already loaded in the R session
# ==============================================================================

# ==============================================================================
# Assign domain and core variables
# ==============================================================================

ti <- raw_ti %>%
  mutate(
    # STUDYID: Study Identifier (from source)
    STUDYID = STUDYID,
    
    # DOMAIN: Domain Abbreviation
    DOMAIN = "TI",
    
    # TIRL: Inclusion/Exclusion Criterion Rule
    TIRL = if ("TIRL" %in% names(.)) {
      TIRL
    } else if ("IE_RULE" %in% names(.)) {
      IE_RULE
    } else {
      NA_character_
    },
    
    # IETESTCD: Incl/Excl Criterion Short Name
    IETESTCD = if ("IETESTCD" %in% names(.)) {
      IETESTCD
    } else if ("IE_TESTCD" %in% names(.)) {
      IE_TESTCD
    } else if ("TESTCD" %in% names(.)) {
      TESTCD
    } else {
      NA_character_
    },
    
    # IETEST: Inclusion/Exclusion Criterion
    IETEST = if ("IETEST" %in% names(.)) {
      IETEST
    } else if ("IE_TEST" %in% names(.)) {
      IE_TEST
    } else if ("TEST" %in% names(.)) {
      TEST
    } else {
      NA_character_
    },
    
    # IECAT: Inclusion/Exclusion Category
    IECAT = if ("IECAT" %in% names(.)) {
      IECAT
    } else if ("IE_CAT" %in% names(.)) {
      IE_CAT
    } else if ("CAT" %in% names(.)) {
      CAT
    } else {
      NA_character_
    },
    
    # IESCAT: Inclusion/Exclusion Subcategory
    IESCAT = if ("IESCAT" %in% names(.)) {
      IESCAT
    } else if ("IE_SCAT" %in% names(.)) {
      IE_SCAT
    } else if ("SCAT" %in% names(.)) {
      SCAT
    } else {
      NA_character_
    },
    
    # TIVERS: Protocol Criteria Versions
    TIVERS = if ("TIVERS" %in% names(.)) {
      TIVERS
    } else if ("VERS" %in% names(.)) {
      VERS
    } else if ("VERSION" %in% names(.)) {
      VERSION
    } else {
      NA_character_
    }
  )

# ==============================================================================
# Select only spec variables in order and sort
# Variable order from specification:
# STUDYID, DOMAIN, IETESTCD, IETEST, IECAT, IESCAT, TIRL, TIVERS
# ==============================================================================

ti <- ti %>%
  arrange(STUDYID, IETESTCD) %>%
  select(
    STUDYID,    # Study Identifier
    DOMAIN,     # Domain Abbreviation
    IETESTCD,   # Incl/Excl Criterion Short Name
    IETEST,     # Inclusion/Exclusion Criterion
    IECAT,      # Inclusion/Exclusion Category
    IESCAT,     # Inclusion/Exclusion Subcategory
    TIRL,       # Inclusion/Exclusion Criterion Rule
    TIVERS      # Protocol Criteria Versions
  )

# -- END TI -- #

# ==============================================================================
# End of Program
# ==============================================================================

# -- Verification -- #
# glimpse(ti)
# table(ti$DOMAIN)

# End of ti.R
