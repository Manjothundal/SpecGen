# ********************************************************************
# Program:    ts.R
# Domain:     TS (General)
# Purpose:    Create SDTM TS domain data frame
# Variables:  10
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     ts data frame (TS domain dataset)
#
# Variables:  STUDYID, DOMAIN, TSSEQ, TSGRPID, TSPARMCD, TSPARM, TSVAL, TSVALCD
#             ...
# ********************************************************************

# ==============================================================================
# Program: ts_domain.R
# Purpose: Create SDTM TS (Trial Summary) domain
# SDTM Version: 3.2
# ==============================================================================

library(dplyr)

# -- BEGIN TS --

# ==============================================================================
# Section 1: Read source data
# ==============================================================================
# Assume raw_ts is already loaded in the R session

# ==============================================================================
# Section 2: Derive base TS domain
# ==============================================================================

ts <- raw_ts %>%
  # ==============================================================================
  # Section 3: Ensure STUDYID is present
  # ==============================================================================
  mutate(
    STUDYID = if ("STUDYID" %in% names(raw_ts)) STUDYID else NA_character_
  ) %>%
  
  # Assign DOMAIN
  mutate(DOMAIN = "TS") %>%
  
  # ==============================================================================
  # Section 4: Map protocol-defined parameters
  # ==============================================================================
  # Map TSPARMCD (Trial Summary Parameter Short Name)
  # Map TSPARM (Trial Summary Parameter)
  # Map TSVAL (Parameter Value)
  # Map TSVALCD (Parameter Value Code) if applicable
  mutate(
    TSPARMCD = if ("TSPARMCD" %in% names(raw_ts)) as.character(TSPARMCD) else NA_character_,
    TSPARM = if ("TSPARM" %in% names(raw_ts)) as.character(TSPARM) else NA_character_,
    TSVAL = if ("TSVAL" %in% names(raw_ts)) as.character(TSVAL) else NA_character_,
    TSVALCD = if ("TSVALCD" %in% names(raw_ts)) as.character(TSVALCD) else NA_character_
  ) %>%
  
  # ==============================================================================
  # Section 5: Map reference terminology variables
  # ==============================================================================
  # TSVCDREF: Name of the Reference Terminology
  # TSVCDVER: Version of the Reference Terminology
  mutate(
    TSVCDREF = if ("TSVCDREF" %in% names(raw_ts)) as.character(TSVCDREF) else NA_character_,
    TSVCDVER = if ("TSVCDVER" %in% names(raw_ts)) as.character(TSVCDVER) else NA_character_
  ) %>%
  
  # ==============================================================================
  # Section 6: Map TSGRPID (Group ID)
  # ==============================================================================
  mutate(
    TSGRPID = if ("TSGRPID" %in% names(raw_ts)) as.character(TSGRPID) else NA_character_
  ) %>%
  
  # ==============================================================================
  # Section 7: Derive TSSEQ (Sequence Number)
  # ==============================================================================
  # Note: TS is a trial-level domain, not subject-level
  # TSSEQ is a simple sequence number for each parameter
  arrange(STUDYID, TSGRPID, TSPARMCD) %>%
  mutate(TSSEQ = row_number()) %>%
  
  # ==============================================================================
  # Section 8: Final sort
  # ==============================================================================
  arrange(STUDYID, TSSEQ) %>%
  
  # ==============================================================================
  # Section 9: Select and order variables per SDTM specification
  # ==============================================================================
  # Variable labels (for reference only - R does not require label statements):
  # STUDYID: Study Identifier
  # DOMAIN: Domain Abbreviation
  # TSSEQ: Sequence Number
  # TSGRPID: Group ID
  # TSPARMCD: Trial Summary Parameter Short Name
  # TSPARM: Trial Summary Parameter
  # TSVAL: Parameter Value
  # TSVALCD: Parameter Value Code
  # TSVCDREF: Name of the Reference Terminology
  # TSVCDVER: Version of the Reference Terminology
  select(
    STUDYID,
    DOMAIN,
    TSSEQ,
    TSGRPID,
    TSPARMCD,
    TSPARM,
    TSVAL,
    TSVALCD,
    TSVCDREF,
    TSVCDVER
  )

# -- END TS --

# ==============================================================================
# End of Program
# ==============================================================================

# -- Verification -- #
# glimpse(ts)
# table(ts$DOMAIN)

# End of ts.R
