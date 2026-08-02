# ********************************************************************
# Program:    ex.R
# Domain:     EX (Interventions)
# Purpose:    Create SDTM EX domain data frame
# Variables:  16
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     ex data frame (EX domain dataset)
#
# Variables:  STUDYID, EXSEQ, USUBJID, DOMAIN, EXTRT, EXDECOD, EXCAT, EXDOSE
#             ...
# ********************************************************************

# ==============================================================================
# Program:      EX Domain (Exposure / Interventions)
# Purpose:      Create SDTM EX domain from source data
# CDISC Model:  SDTM 3.x
# ==============================================================================

library(dplyr)

# -- BEGIN EX -- #

# ==============================================================================
# 1. Load and prepare source data
# ==============================================================================
# raw_ex and dm are already loaded in the R session

# ==============================================================================
# 2. Build EX domain from raw_ex
# ==============================================================================

ex <- raw_ex %>%
  
  # --------------------------------------------------------------------------
  # Derive USUBJID from dm or construct from identifiers
  # --------------------------------------------------------------------------
  left_join(
    dm %>% select(STUDYID, SITEID, SUBJID, USUBJID, RFSTDTC),
    by = c("STUDYID", "SITEID", "SUBJID")
  ) %>%
  
  # If USUBJID not in dm, construct it
  mutate(
    USUBJID = if_else(
      is.na(USUBJID),
      paste(STUDYID, SITEID, SUBJID, sep = "-"),
      USUBJID
    )
  ) %>%
  
  # --------------------------------------------------------------------------
  # Assign DOMAIN
  # --------------------------------------------------------------------------
  # Domain Abbreviation
  mutate(DOMAIN = "EX") %>%
  
  # --------------------------------------------------------------------------
  # Map treatment variables from source
  # --------------------------------------------------------------------------
  # Reported Name of Treatment
  mutate(EXTRT = as.character(TRT)) %>%
  # Standardized Treatment Name
  mutate(EXDECOD = as.character(TRTDECOD)) %>%
  # Category for Intervention
  mutate(EXCAT = as.character(TRTCAT)) %>%
  
  # --------------------------------------------------------------------------
  # Map dosing variables from source
  # --------------------------------------------------------------------------
  # Dose per Administration
  mutate(EXDOSE = as.numeric(DOSE)) %>%
  # Dose Units
  mutate(EXDOSU = as.character(DOSEU)) %>%
  # Dosing Frequency per Interval
  mutate(EXDOSFRQ = as.character(DOSFRQ)) %>%
  # Route of Administration
  mutate(EXROUTE = as.character(ROUTE)) %>%
  
  # --------------------------------------------------------------------------
  # Map start and end dates (ISO 8601 character format)
  # --------------------------------------------------------------------------
  # Start Date/Time of Intervention
  mutate(EXSTDTC = as.character(STDAT)) %>%
  # End Date/Time of Intervention
  mutate(EXENDTC = as.character(ENDAT)) %>%
  
  # --------------------------------------------------------------------------
  # Derive study days relative to RFSTDTC from dm
  # --------------------------------------------------------------------------
  mutate(
    # Study Day of Start of Intervention
    EXSTDY = case_when(
      is.na(EXSTDTC) | is.na(RFSTDTC) ~ NA_real_,
      TRUE ~ as.numeric(as.Date(substr(EXSTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 
             if_else(as.Date(substr(EXSTDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1, 0)
    ),
    # Study Day of End of Intervention
    EXENDY = case_when(
      is.na(EXENDTC) | is.na(RFSTDTC) ~ NA_real_,
      TRUE ~ as.numeric(as.Date(substr(EXENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 
             if_else(as.Date(substr(EXENDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1, 0)
    )
  ) %>%
  
  # --------------------------------------------------------------------------
  # Derive EPOCH based on date relative to treatment period
  # --------------------------------------------------------------------------
  # Epoch
  mutate(
    EPOCH = case_when(
      is.na(EXSTDTC) ~ NA_character_,
      EXSTDY < 1 ~ "SCREENING",
      EXSTDY >= 1 ~ "TREATMENT",
      TRUE ~ NA_character_
    )
  ) %>%
  
  # --------------------------------------------------------------------------
  # Sort by subject
  # --------------------------------------------------------------------------
  arrange(STUDYID, USUBJID, EXSTDTC, EXTRT) %>%
  
  # --------------------------------------------------------------------------
  # Derive EXSEQ as sequence number within each subject
  # --------------------------------------------------------------------------
  group_by(USUBJID) %>%
  # Sequence Number
  mutate(EXSEQ = row_number()) %>%
  ungroup() %>%
  
  # --------------------------------------------------------------------------
  # Final sort
  # --------------------------------------------------------------------------
  arrange(STUDYID, USUBJID, EXSEQ) %>%
  
  # --------------------------------------------------------------------------
  # Select only SDTM variables in specification order
  # --------------------------------------------------------------------------
  select(
    STUDYID,      # Study Identifier
    DOMAIN,       # Domain Abbreviation
    USUBJID,      # Unique Subject Identifier
    EXSEQ,        # Sequence Number
    EXTRT,        # Reported Name of Treatment
    EXDECOD,      # Standardized Treatment Name
    EXCAT,        # Category for Intervention
    EXDOSE,       # Dose per Administration
    EXDOSU,       # Dose Units
    EXDOSFRQ,     # Dosing Frequency per Interval
    EXROUTE,      # Route of Administration
    EXSTDTC,      # Start Date/Time of Intervention
    EXENDTC,      # End Date/Time of Intervention
    EXSTDY,       # Study Day of Start of Intervention
    EXENDY,       # Study Day of End of Intervention
    EPOCH         # Epoch
  )

# -- END EX -- #

# -- Verification -- #
# glimpse(ex)
# table(ex$DOMAIN)

# End of ex.R
