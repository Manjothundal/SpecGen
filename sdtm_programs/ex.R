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
# Program:      ex_domain.R
# Purpose:      Create SDTM EX (Exposure) domain
# SDTM Version: 3.2
# ==============================================================================

library(dplyr)

# -- BEGIN EX -- #

# ==============================================================================
# Read source data
# Assumes raw_ex and dm are already loaded in the R session
# ==============================================================================

# ==============================================================================
# Derive USUBJID and map core variables
# ==============================================================================

ex <- raw_ex %>%
  # Derive USUBJID (join from DM or construct if needed)
  left_join(
    dm %>% select(STUDYID, SITEID, SUBJID, USUBJID, RFSTDTC),
    by = c("STUDYID", "SITEID", "SUBJID")
  ) %>%
  
  # If USUBJID not in DM, construct it
  mutate(
    USUBJID = if_else(
      is.na(USUBJID),
      paste(STUDYID, SITEID, SUBJID, sep = "-"),
      USUBJID
    )
  ) %>%
  
  # Assign Domain
  mutate(
    DOMAIN = "EX"  # Domain Abbreviation
  ) %>%
  
  # Map treatment variables
  mutate(
    EXTRT = EXRAW_TRT,           # Reported Name of Treatment
    EXDECOD = EXSTD_TRT,         # Standardized Treatment Name
    EXCAT = EXCAT_RAW            # Category for Intervention
  ) %>%
  
  # Map dosing variables
  mutate(
    EXDOSE = as.numeric(EXDOSE_RAW),    # Dose per Administration
    EXDOSU = EXDOSU_RAW,                # Dose Units
    EXDOSFRQ = EXDOSFRQ_RAW,            # Dosing Frequency per Interval
    EXROUTE = EXROUTE_RAW               # Route of Administration
  ) %>%
  
  # Map date/time variables (ISO 8601 format)
  mutate(
    EXSTDTC = EXSTDAT,           # Start Date/Time of Intervention
    EXENDTC = EXENDAT            # End Date/Time of Intervention
  ) %>%
  
  # ==============================================================================
  # Derive Study Days (EXSTDY, EXENDY)
  # Study day = date - RFSTDTC + 1 if date >= RFSTDTC
  #           = date - RFSTDTC     if date < RFSTDTC
  # ==============================================================================
  mutate(
    # Parse start date
    EXSTDT = if_else(
      !is.na(EXSTDTC) & nchar(EXSTDTC) >= 10,
      as.Date(substr(EXSTDTC, 1, 10)),
      as.Date(NA_character_)
    ),
    # Parse end date
    EXENDT = if_else(
      !is.na(EXENDTC) & nchar(EXENDTC) >= 10,
      as.Date(substr(EXENDTC, 1, 10)),
      as.Date(NA_character_)
    ),
    # Parse reference start date
    RFSTDT = if_else(
      !is.na(RFSTDTC) & nchar(RFSTDTC) >= 10,
      as.Date(substr(RFSTDTC, 1, 10)),
      as.Date(NA_character_)
    )
  ) %>%
  mutate(
    # Study Day of Start of Intervention
    EXSTDY = case_when(
      is.na(EXSTDT) | is.na(RFSTDT) ~ NA_real_,
      EXSTDT >= RFSTDT ~ as.numeric(EXSTDT - RFSTDT) + 1,
      EXSTDT < RFSTDT ~ as.numeric(EXSTDT - RFSTDT)
    ),
    # Study Day of End of Intervention
    EXENDY = case_when(
      is.na(EXENDT) | is.na(RFSTDT) ~ NA_real_,
      EXENDT >= RFSTDT ~ as.numeric(EXENDT - RFSTDT) + 1,
      EXENDT < RFSTDT ~ as.numeric(EXENDT - RFSTDT)
    )
  ) %>%
  
  # ==============================================================================
  # Derive EPOCH based on treatment period
  # Assign based on start date relative to planned treatment phases
  # ==============================================================================
  mutate(
    EPOCH = case_when(
      is.na(EXSTDT) ~ NA_character_,
      EXCAT == "SCREENING" ~ "SCREENING",
      EXCAT == "RUN-IN" ~ "RUN-IN",
      EXCAT == "TREATMENT" ~ "TREATMENT",
      EXCAT == "FOLLOW-UP" ~ "FOLLOW-UP",
      TRUE ~ "TREATMENT"  # Default epoch
    )
  ) %>%
  
  # ==============================================================================
  # Derive EXSEQ (Sequence Number within subject)
  # ==============================================================================
  arrange(STUDYID, USUBJID, EXSTDTC, EXENDTC, EXTRT) %>%
  group_by(USUBJID) %>%
  mutate(EXSEQ = row_number()) %>%
  ungroup() %>%
  
  # ==============================================================================
  # Final sort
  # ==============================================================================
  arrange(STUDYID, USUBJID, EXSEQ) %>%
  
  # ==============================================================================
  # Select final variables in specification order
  # Note: R does not support variable labels, lengths, or formats in base data frames
  # Labels are documented in comments below
  # ==============================================================================
  select(
    STUDYID,   # Study Identifier
    DOMAIN,    # Domain Abbreviation
    USUBJID,   # Unique Subject Identifier
    EXSEQ,     # Sequence Number
    EXTRT,     # Reported Name of Treatment
    EXDECOD,   # Standardized Treatment Name
    EXCAT,     # Category for Intervention
    EXDOSE,    # Dose per Administration
    EXDOSU,    # Dose Units
    EXDOSFRQ,  # Dosing Frequency per Interval
    EXROUTE,   # Route of Administration
    EXSTDTC,   # Start Date/Time of Intervention
    EXENDTC,   # End Date/Time of Intervention
    EXSTDY,    # Study Day of Start of Intervention
    EXENDY,    # Study Day of End of Intervention
    EPOCH      # Epoch
  )

# -- END EX -- #

# -- Verification -- #
# glimpse(ex)
# table(ex$DOMAIN)

# End of ex.R
