# ********************************************************************
# Program:    mh.R
# Domain:     MH (Events)
# Purpose:    Create SDTM MH domain data frame
# Variables:  15
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     mh data frame (MH domain dataset)
#
# Variables:  STUDYID, MHSEQ, USUBJID, DOMAIN, MHTERM, MHDECOD, MHCAT, MHSCAT
#             ...
# ********************************************************************

# ==============================================================================
# Program:      mh.R
# Description:  SDTM MH (Medical History) Domain Derivation
# SDTM Version: 3.2
# Input:        raw_mh, dm (already in R session)
# Output:       mh
# ==============================================================================

# -- BEGIN MH -- #

library(dplyr)

# ==============================================================================
# Derive MH domain
# ==============================================================================

mh <- raw_mh %>%
  
  # ----------------------------------------------------------------------------
  # Merge with DM to get STUDYID, USUBJID, and RFSTDTC
  # ----------------------------------------------------------------------------
  left_join(
    dm %>% select(USUBJID, STUDYID, RFSTDTC, RFXSTDTC, RFXENDTC),
    by = "USUBJID"
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Assign Domain
  # Domain Abbreviation
  # ----------------------------------------------------------------------------
  mutate(
    DOMAIN = "MH"
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Map terms and coded terms
  # MHTERM: Reported Term for the Event
  # MHDECOD: Dictionary-Derived Term
  # ----------------------------------------------------------------------------
  mutate(
    MHTERM = MHTERM,
    MHDECOD = MHDECOD
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Map category and subcategory
  # MHCAT: Category for Event
  # MHSCAT: Subcategory for Event
  # ----------------------------------------------------------------------------
  mutate(
    MHCAT = MHCAT,
    MHSCAT = MHSCAT
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Map body system or organ class
  # MHBODSYS: Body System or Organ Class
  # ----------------------------------------------------------------------------
  mutate(
    MHBODSYS = MHBODSYS
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Map start and end dates
  # MHSTDTC: Start Date/Time of Event (ISO 8601)
  # MHENDTC: End Date/Time of Event (ISO 8601)
  # ----------------------------------------------------------------------------
  mutate(
    MHSTDTC = MHSTDTC,
    MHENDTC = MHENDTC
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Derive study days
  # MHSTDY: Study Day of Start of Event
  # MHENDY: Study Day of End of Event
  # ----------------------------------------------------------------------------
  mutate(
    RFSTDT = as.Date(substr(RFSTDTC, 1, 10)),
    MHSTDT = as.Date(substr(MHSTDTC, 1, 10)),
    MHENDT = as.Date(substr(MHENDTC, 1, 10)),
    
    MHSTDY = case_when(
      is.na(MHSTDT) | is.na(RFSTDT) ~ NA_real_,
      MHSTDT >= RFSTDT ~ as.numeric(MHSTDT - RFSTDT) + 1,
      MHSTDT < RFSTDT ~ as.numeric(MHSTDT - RFSTDT)
    ),
    
    MHENDY = case_when(
      is.na(MHENDT) | is.na(RFSTDT) ~ NA_real_,
      MHENDT >= RFSTDT ~ as.numeric(MHENDT - RFSTDT) + 1,
      MHENDT < RFSTDT ~ as.numeric(MHENDT - RFSTDT)
    )
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Derive EPOCH based on date relative to treatment period
  # EPOCH: Epoch
  # ----------------------------------------------------------------------------
  mutate(
    RFXSTDT = as.Date(substr(RFXSTDTC, 1, 10)),
    RFXENDT = as.Date(substr(RFXENDTC, 1, 10)),
    
    EPOCH = case_when(
      is.na(MHSTDT) ~ NA_character_,
      !is.na(RFXSTDT) & MHSTDT < RFXSTDT ~ "SCREENING",
      !is.na(RFXSTDT) & !is.na(RFXENDT) & MHSTDT >= RFXSTDT & MHSTDT <= RFXENDT ~ "TREATMENT",
      !is.na(RFXENDT) & MHSTDT > RFXENDT ~ "FOLLOW-UP",
      !is.na(RFSTDT) & MHSTDT < RFSTDT ~ "SCREENING",
      TRUE ~ "TREATMENT"
    )
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Map ongoing flag
  # MHENRF: Ongoing?: Yes No
  # ----------------------------------------------------------------------------
  mutate(
    MHENRF = MHENRF
  ) %>%
  
  # ----------------------------------------------------------------------------
  # Derive sequence number
  # MHSEQ: Sequence Number
  # ----------------------------------------------------------------------------
  group_by(USUBJID) %>%
  arrange(USUBJID, MHSTDTC, MHTERM) %>%
  mutate(
    MHSEQ = row_number()
  ) %>%
  ungroup() %>%
  
  # ----------------------------------------------------------------------------
  # Final sort
  # ----------------------------------------------------------------------------
  arrange(STUDYID, USUBJID, MHSEQ) %>%
  
  # ----------------------------------------------------------------------------
  # Select and order final variables per SDTM specification
  # ----------------------------------------------------------------------------
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    MHSEQ,
    MHTERM,
    MHDECOD,
    MHCAT,
    MHSCAT,
    MHBODSYS,
    MHSTDTC,
    MHENDTC,
    MHSTDY,
    MHENDY,
    EPOCH,
    MHENRF
  )

# -- END MH -- #

# -- Verification -- #
# glimpse(mh)
# table(mh$DOMAIN)

# End of mh.R
