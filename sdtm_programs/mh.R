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
# SDTM MH Domain - Medical History
# One row per medical history event per subject
# ==============================================================================

library(dplyr)

# -- BEGIN MH -- #

# ==============================================================================
# 1. Read source data (raw_mh and dm already available in session)
# ==============================================================================

# ==============================================================================
# 2. Derive USUBJID and merge with DM for reference dates
# ==============================================================================

mh <- raw_mh %>%
  # Derive USUBJID if not already present
  mutate(
    USUBJID = if ("USUBJID" %in% names(.)) USUBJID else paste(STUDYID, SITEID, SUBJID, sep = "-")
  ) %>%
  # Join with DM to get RFSTDTC for study day calculations
  left_join(
    dm %>% select(USUBJID, RFSTDTC, any_of(c("RFXSTDTC", "RFXENDTC"))),
    by = "USUBJID"
  )

# ==============================================================================
# 3. Assign DOMAIN
# ==============================================================================

mh <- mh %>%
  mutate(DOMAIN = "MH")

# ==============================================================================
# 4. Map Medical History Terms (MHTERM, MHDECOD)
# ==============================================================================

mh <- mh %>%
  mutate(
    # MHTERM: Reported Term for the Event
    MHTERM = case_when(
      "MHTERM" %in% names(.) ~ MHTERM,
      "MH_VERBATIM" %in% names(.) ~ MH_VERBATIM,
      "VERBATIM" %in% names(.) ~ VERBATIM,
      TRUE ~ NA_character_
    ),
    
    # MHDECOD: Dictionary-Derived Term
    MHDECOD = case_when(
      "MHDECOD" %in% names(.) ~ MHDECOD,
      "MH_CODED" %in% names(.) ~ MH_CODED,
      "CODED_TERM" %in% names(.) ~ CODED_TERM,
      TRUE ~ MHTERM
    )
  )

# ==============================================================================
# 5. Map Body System (MHBODSYS)
# ==============================================================================

mh <- mh %>%
  mutate(
    # MHBODSYS: Body System or Organ Class
    MHBODSYS = case_when(
      "MHBODSYS" %in% names(.) ~ MHBODSYS,
      "MH_BODSYS" %in% names(.) ~ MH_BODSYS,
      "BODSYS" %in% names(.) ~ BODSYS,
      "SOC" %in% names(.) ~ SOC,
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# 6. Map Categories (MHCAT, MHSCAT)
# ==============================================================================

mh <- mh %>%
  mutate(
    # MHCAT: Category for Event
    MHCAT = case_when(
      "MHCAT" %in% names(.) ~ MHCAT,
      "MH_CAT" %in% names(.) ~ MH_CAT,
      "CATEGORY" %in% names(.) ~ CATEGORY,
      TRUE ~ NA_character_
    ),
    
    # MHSCAT: Subcategory for Event
    MHSCAT = case_when(
      "MHSCAT" %in% names(.) ~ MHSCAT,
      "MH_SCAT" %in% names(.) ~ MH_SCAT,
      "SUBCATEGORY" %in% names(.) ~ SUBCATEGORY,
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# 7. Map Start and End Date/Time (MHSTDTC, MHENDTC)
# ==============================================================================

mh <- mh %>%
  mutate(
    # MHSTDTC: Start Date/Time of Event (ISO 8601 character format)
    MHSTDTC = case_when(
      "MHSTDTC" %in% names(.) ~ MHSTDTC,
      "MH_STDAT" %in% names(.) ~ MH_STDAT,
      "START_DATE" %in% names(.) ~ START_DATE,
      "STDAT" %in% names(.) ~ STDAT,
      TRUE ~ NA_character_
    ),
    
    # MHENDTC: End Date/Time of Event (ISO 8601 character format)
    MHENDTC = case_when(
      "MHENDTC" %in% names(.) ~ MHENDTC,
      "MH_ENDAT" %in% names(.) ~ MH_ENDAT,
      "END_DATE" %in% names(.) ~ END_DATE,
      "ENDAT" %in% names(.) ~ ENDAT,
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# 8. Map Ongoing Flag (MHENRF)
# ==============================================================================

mh <- mh %>%
  mutate(
    # MHENRF: Ongoing flag
    MHENRF = case_when(
      "MHENRF" %in% names(.) ~ MHENRF,
      "MH_ONGOING" %in% names(.) ~ MH_ONGOING,
      "ONGOING" %in% names(.) ~ ONGOING,
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# 9. Derive Study Days (MHSTDY, MHENDY)
# ==============================================================================

mh <- mh %>%
  mutate(
    # Parse reference start date
    RFSTDTC_DATE = if_else(!is.na(RFSTDTC), as.Date(substr(RFSTDTC, 1, 10)), as.Date(NA_character_)),
    
    # Parse start date
    MHSTDTC_DATE = if_else(!is.na(MHSTDTC), as.Date(substr(MHSTDTC, 1, 10)), as.Date(NA_character_)),
    
    # Parse end date
    MHENDTC_DATE = if_else(!is.na(MHENDTC), as.Date(substr(MHENDTC, 1, 10)), as.Date(NA_character_)),
    
    # MHSTDY: Study Day of Start of Event
    MHSTDY = if_else(
      !is.na(MHSTDTC_DATE) & !is.na(RFSTDTC_DATE),
      as.numeric(MHSTDTC_DATE - RFSTDTC_DATE) + if_else(MHSTDTC_DATE >= RFSTDTC_DATE, 1, 0),
      NA_real_
    ),
    
    # MHENDY: Study Day of End of Event
    MHENDY = if_else(
      !is.na(MHENDTC_DATE) & !is.na(RFSTDTC_DATE),
      as.numeric(MHENDTC_DATE - RFSTDTC_DATE) + if_else(MHENDTC_DATE >= RFSTDTC_DATE, 1, 0),
      NA_real_
    )
  )

# ==============================================================================
# 10. Derive EPOCH based on date relative to treatment period
# ==============================================================================

if (all(c("RFXSTDTC", "RFXENDTC") %in% names(mh))) {
  mh <- mh %>%
    mutate(
      RFXSTDTC_DATE = if_else(!is.na(RFXSTDTC), as.Date(substr(RFXSTDTC, 1, 10)), as.Date(NA_character_)),
      RFXENDTC_DATE = if_else(!is.na(RFXENDTC), as.Date(substr(RFXENDTC, 1, 10)), as.Date(NA_character_)),
      
      # Derive EPOCH
      EPOCH = case_when(
        is.na(MHSTDTC_DATE) ~ NA_character_,
        !is.na(RFXSTDTC_DATE) & MHSTDTC_DATE < RFXSTDTC_DATE ~ "SCREENING",
        !is.na(RFXSTDTC_DATE) & !is.na(RFXENDTC_DATE) & 
          MHSTDTC_DATE >= RFXSTDTC_DATE & MHSTDTC_DATE <= RFXENDTC_DATE ~ "TREATMENT",
        !is.na(RFXENDTC_DATE) & MHSTDTC_DATE > RFXENDTC_DATE ~ "FOLLOW-UP",
        TRUE ~ NA_character_
      )
    ) %>%
    select(-RFXSTDTC, -RFXENDTC, -RFXSTDTC_DATE, -RFXENDTC_DATE)
} else {
  mh <- mh %>%
    mutate(EPOCH = NA_character_)
}

# ==============================================================================
# 11. Derive MHSEQ (Sequence Number within subject)
# ==============================================================================

mh <- mh %>%
  arrange(STUDYID, USUBJID, MHSTDTC, MHTERM) %>%
  group_by(USUBJID) %>%
  mutate(MHSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# 12. Remove temporary variables and sort
# ==============================================================================

mh <- mh %>%
  select(-RFSTDTC, -RFSTDTC_DATE, -MHSTDTC_DATE, -MHENDTC_DATE) %>%
  arrange(STUDYID, USUBJID, MHSEQ)

# ==============================================================================
# 13. Select final variables in specification order
# ==============================================================================

mh <- mh %>%
  select(
    STUDYID,
    MHSEQ,
    USUBJID,
    DOMAIN,
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
