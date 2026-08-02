# ********************************************************************
# Program:    tv.R
# Domain:     TV (General)
# Purpose:    Create SDTM TV domain data frame
# Variables:  9
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     tv data frame (TV domain dataset)
#
# Variables:  STUDYID, DOMAIN, VISITNUM, VISIT, VISITDY, ARMCD, TVSTRL, TVENRL
#             ...
# ********************************************************************

# ==============================================================================
# SDTM TV Domain: Trial Visits
# Production R script (tidyverse / dplyr)
# ==============================================================================

library(dplyr)

# -- BEGIN TV --

# ==============================================================================
# Read source data
# Assumption: raw_tv and dm are already loaded in the R session
# ==============================================================================

# ==============================================================================
# Derive TV domain
# TV domain is at the protocol level, not subject level
# USUBJID is not needed or used in TV
# ==============================================================================

tv <- raw_tv %>%
  
  # ==============================================================================
  # Assign domain
  # ==============================================================================
  mutate(
    DOMAIN = "TV"
  ) %>%
  
  # ==============================================================================
  # Map protocol variables
  # Assuming raw_tv contains: STUDYID, VISITNUM, VISIT, VISITDY, ARMCD, ARM, TVSTRL, TVENRL
  # ==============================================================================
  mutate(
    # STUDYID: Study Identifier (Char)
    STUDYID = as.character(STUDYID),
    
    # VISITNUM: Visit Number (Num) - from raw_tv
    VISITNUM = as.numeric(VISITNUM),
    
    # VISIT: Visit Name (Char) - from raw_tv
    VISIT = as.character(VISIT),
    
    # VISITDY: Planned Study Day of Visit (Num) - from raw_tv
    VISITDY = as.numeric(VISITDY),
    
    # ARMCD: Planned Arm Code (Char) - from raw_tv
    ARMCD = as.character(ARMCD),
    
    # TVSTRL: Visit Start Rule (Char) - from raw_tv
    TVSTRL = as.character(TVSTRL),
    
    # TVENRL: Visit End Rule (Char) - from raw_tv
    TVENRL = as.character(TVENRL),
    
    # ARM: Description of Planned Arm (Char) - from raw_tv
    ARM = as.character(ARM)
  ) %>%
  
  # ==============================================================================
  # Sort final dataset
  # ==============================================================================
  arrange(STUDYID, ARMCD, VISITNUM) %>%
  
  # ==============================================================================
  # Select only specified variables in order per SDTM spec
  # Variable         Label                                         Type
  # STUDYID          Study Identifier                              Char
  # DOMAIN           Domain Abbreviation                           Char
  # VISITNUM         Visit Number                                  Num
  # VISIT            Visit Name                                    Char
  # VISITDY          Planned Study Day of Visit                    Num
  # ARMCD            Planned Arm Code                              Char
  # TVSTRL           Visit Start Rule                              Char
  # TVENRL           Visit End Rule                                Char
  # ARM              Description of Planned Arm                    Char
  # ==============================================================================
  select(
    STUDYID,
    DOMAIN,
    VISITNUM,
    VISIT,
    VISITDY,
    ARMCD,
    TVSTRL,
    TVENRL,
    ARM
  )

# -- END TV --

# -- Verification -- #
# glimpse(tv)
# table(tv$DOMAIN)

# End of tv.R
