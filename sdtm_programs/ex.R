# ********************************************************************
# Program:    ex.R
# Domain:     EX (Interventions)
# Purpose:    Create SDTM EX domain data frame
# Variables:  16
#
# Output:     ex data frame (EX domain dataset)
#
# Variables:  STUDYID, EXSEQ, USUBJID, DOMAIN, EXTRT, EXDECOD, EXCAT, EXDOSE,
#             EXDOSU, EXDOSFRQ, EXROUTE, EXSTDTC, EXENDTC, EXSTDY, EXENDY, EPOCH
# ********************************************************************

library(dplyr)

# -- BEGIN EX -- #

ex <- raw_ex %>%
  # --------------------------------------------------------------------------
  # Merge with DM to get reference dates and subject identifiers
  # --------------------------------------------------------------------------
  left_join(
    dm %>% select(STUDYID, USUBJID, RFSTDTC),
    by = c("STUDYID", "USUBJID")
  ) %>%
  
  # --------------------------------------------------------------------------
  # Assign domain constant
  # --------------------------------------------------------------------------
  mutate(
    # DOMAIN: Domain Abbreviation
    DOMAIN = "EX"
  ) %>%
  
  # --------------------------------------------------------------------------
  # Map treatment variables
  # --------------------------------------------------------------------------
  mutate(
    # EXTRT: Reported Name of Treatment
    EXTRT = as.character(TRT),
    
    # EXDECOD: Standardized Treatment Name
    EXDECOD = as.character(TRTDECOD)
  ) %>%
  
  # --------------------------------------------------------------------------
  # Map category
  # --------------------------------------------------------------------------
  mutate(
    # EXCAT: Category for Intervention
    EXCAT = as.character(CAT)
  ) %>%
  
  # --------------------------------------------------------------------------
  # Map dosing variables
  # --------------------------------------------------------------------------
  mutate(
    # EXDOSE: Dose per Administration
    EXDOSE = as.numeric(DOSE),
    
    # EXDOSU: Dose Units
    EXDOSU = as.character(DOSU),
    
    # EXDOSFRQ: Dosing Frequency per Interval
    EXDOSFRQ = as.character(DOSFRQ),
    
    # EXROUTE: Route of Administration
    EXROUTE = as.character(ROUTE)
  ) %>%
  
  # --------------------------------------------------------------------------
  # Map date/time variables (ISO 8601 format)
  # --------------------------------------------------------------------------
  mutate(
    # EXSTDTC: Start Date/Time of Intervention
    EXSTDTC = as.character(STDTC),
    
    # EXENDTC: End Date/Time of Intervention
    EXENDTC = as.character(ENDTC)
  ) %>%
  
  # --------------------------------------------------------------------------
  # Derive study days
  # --------------------------------------------------------------------------
  mutate(
    # EXSTDY: Study Day of Start of Intervention
    EXSTDY = case_when(
      is.na(EXSTDTC) | is.na(RFSTDTC) ~ NA_real_,
      TRUE ~ as.numeric(as.Date(substr(EXSTDTC, 1, 10)) - 
                        as.Date(substr(RFSTDTC, 1, 10))) +
             if_else(as.Date(substr(EXSTDTC, 1, 10)) >= 
                    as.Date(substr(RFSTDTC, 1, 10)), 1, 0)
    ),
    
    # EXENDY: Study Day of End of Intervention
    EXENDY = case_when(
      is.na(EXENDTC) | is.na(RFSTDTC) ~ NA_real_,
      TRUE ~ as.numeric(as.Date(substr(EXENDTC, 1, 10)) - 
                        as.Date(substr(RFSTDTC, 1, 10))) +
             if_else(as.Date(substr(EXENDTC, 1, 10)) >= 
                    as.Date(substr(RFSTDTC, 1, 10)), 1, 0)
    )
  ) %>%
  
  # --------------------------------------------------------------------------
  # Derive epoch based on timing
  # --------------------------------------------------------------------------
  mutate(
    # EPOCH: Epoch
    EPOCH = case_when(
      is.na(EXSTDTC) ~ NA_character_,
      !is.na(EXSTDY) & EXSTDY < 1 ~ "SCREENING",
      !is.na(EXSTDY) & EXSTDY >= 1 ~ "TREATMENT",
      TRUE ~ NA_character_
    )
  ) %>%
  
  # --------------------------------------------------------------------------
  # Derive sequence number
  # --------------------------------------------------------------------------
  arrange(STUDYID, USUBJID, EXSTDTC, EXTRT) %>%
  group_by(USUBJID) %>%
  mutate(
    # EXSEQ: Sequence Number
    EXSEQ = row_number()
  ) %>%
  ungroup() %>%
  
  # --------------------------------------------------------------------------
  # Sort by study, subject, and sequence
  # --------------------------------------------------------------------------
  arrange(STUDYID, USUBJID, EXSEQ) %>%
  
  # --------------------------------------------------------------------------
  # Select final variables in specification order
  # --------------------------------------------------------------------------
  select(
    STUDYID,    # Study Identifier
    EXSEQ,      # Sequence Number
    USUBJID,    # Unique Subject Identifier
    DOMAIN,     # Domain Abbreviation
    EXTRT,      # Reported Name of Treatment
    EXDECOD,    # Standardized Treatment Name
    EXCAT,      # Category for Intervention
    EXDOSE,     # Dose per Administration
    EXDOSU,     # Dose Units
    EXDOSFRQ,   # Dosing Frequency per Interval
    EXROUTE,    # Route of Administration
    EXSTDTC,    # Start Date/Time of Intervention
    EXENDTC,    # End Date/Time of Intervention
    EXSTDY,     # Study Day of Start of Intervention
    EXENDY,     # Study Day of End of Intervention
    EPOCH       # Epoch
  )

# -- END EX -- #

# End of ex.R