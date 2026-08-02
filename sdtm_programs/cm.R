# ********************************************************************
# Program:    cm.R
# Domain:     CM (Interventions)
# Purpose:    Create SDTM CM domain data frame
# Variables:  19
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     cm data frame (CM domain dataset)
#
# Variables:  STUDYID, CMSEQ, USUBJID, DOMAIN, CMTRT, CMDECOD, CMCAT, CMDOSE
#             ...
# ********************************************************************

# ==============================================================================
# Program:       cm.R
# Description:   SDTM CM (Concomitant Medications) Domain Derivation
# Study:         [Study Name]
# Domain:        CM (Interventions Class)
# ==============================================================================

library(dplyr)

# -- BEGIN CM --

# ==============================================================================
# Read source data
# ==============================================================================
# Assumes raw_cm and dm are already loaded in the R session

# ==============================================================================
# Derive USUBJID from DM domain
# ==============================================================================
cm <- raw_cm %>%
  left_join(
    dm %>% select(STUDYID, USUBJID, SITEID, SUBJID, RFSTDTC),
    by = c("STUDYID", "SITEID", "SUBJID")
  )

# ==============================================================================
# Assign DOMAIN
# ==============================================================================
cm <- cm %>%
  mutate(DOMAIN = "CM")

# ==============================================================================
# Map reported and standardized treatment names
# ==============================================================================
# CMTRT: Reported Name of Treatment
# CMDECOD: Standardized Treatment Name
cm <- cm %>%
  mutate(
    CMTRT = if_else(!is.na(CMTRT), as.character(CMTRT), NA_character_),
    CMDECOD = if_else(!is.na(CMDECOD), as.character(CMDECOD), NA_character_)
  )

# ==============================================================================
# Map dosing information
# ==============================================================================
# CMDOSE: Dose per Administration
# CMDOSU: Dose Units (UNIT codelist)
# CMDOSFRQ: Dosing Frequency per Interval (FREQ codelist)
# CMROUTE: Route of Administration (ROUTE codelist)
cm <- cm %>%
  mutate(
    CMDOSE = if_else(!is.na(CMDOSE), as.numeric(CMDOSE), NA_real_),
    CMDOSU = if_else(!is.na(CMDOSU), as.character(CMDOSU), NA_character_),
    CMDOSFRQ = if_else(!is.na(CMDOSFRQ), as.character(CMDOSFRQ), NA_character_),
    CMROUTE = if_else(!is.na(CMROUTE), as.character(CMROUTE), NA_character_)
  )

# ==============================================================================
# Map start and end dates (ISO 8601 format)
# ==============================================================================
# CMSTDTC: Start Date/Time of Intervention
# CMENDTC: End Date/Time of Intervention
cm <- cm %>%
  mutate(
    CMSTDTC = if_else(!is.na(CMSTDTC), as.character(CMSTDTC), NA_character_),
    CMENDTC = if_else(!is.na(CMENDTC), as.character(CMENDTC), NA_character_)
  )

# ==============================================================================
# Derive study day relative to RFSTDTC
# ==============================================================================
# CMSTDY: Study Day of Start of Intervention
# CMENDY: Study Day of End of Intervention
# Study day calculation: if date >= RFSTDTC then (date - RFSTDTC) + 1
#                        if date < RFSTDTC then (date - RFSTDTC)
cm <- cm %>%
  mutate(
    CMSTDY = case_when(
      is.na(CMSTDTC) | is.na(RFSTDTC) ~ NA_real_,
      as.Date(substr(CMSTDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)) ~ 
        as.numeric(as.Date(substr(CMSTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 1,
      TRUE ~ as.numeric(as.Date(substr(CMSTDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10)))
    ),
    CMENDY = case_when(
      is.na(CMENDTC) | is.na(RFSTDTC) ~ NA_real_,
      as.Date(substr(CMENDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)) ~ 
        as.numeric(as.Date(substr(CMENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 1,
      TRUE ~ as.numeric(as.Date(substr(CMENDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10)))
    )
  )

# ==============================================================================
# Derive EPOCH based on date relative to treatment period
# ==============================================================================
# EPOCH: Epoch
# Logic: Assign epoch based on timing of intervention relative to study phases
# This is a simplified derivation; adjust based on study-specific epoch definitions
cm <- cm %>%
  mutate(
    EPOCH = case_when(
      !is.na(CMSTDY) & CMSTDY < 1 ~ "SCREENING",
      !is.na(CMSTDY) & CMSTDY >= 1 ~ "TREATMENT",
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# Map category and other fields
# ==============================================================================
# CMCAT: Category for Intervention
# CMCLAS: ATC Class
# CMINDC: Indication
# CMONGO: Ongoing at Screening?: Yes No (NY codelist)
cm <- cm %>%
  mutate(
    CMCAT = if_else(!is.na(CMCAT), as.character(CMCAT), NA_character_),
    CMCLAS = if_else(!is.na(CMCLAS), as.character(CMCLAS), NA_character_),
    CMINDC = if_else(!is.na(CMINDC), as.character(CMINDC), NA_character_),
    CMONGO = if_else(!is.na(CMONGO), as.character(CMONGO), NA_character_)
  )

# ==============================================================================
# Derive CMSEQ (sequence number within subject)
# ==============================================================================
# CMSEQ: Sequence Number
cm <- cm %>%
  arrange(STUDYID, USUBJID, CMSTDTC, CMTRT) %>%
  group_by(USUBJID) %>%
  mutate(CMSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# Sort and select final variables in specification order
# ==============================================================================
cm <- cm %>%
  arrange(STUDYID, USUBJID, CMSEQ) %>%
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    CMSEQ,
    CMTRT,
    CMDECOD,
    CMCAT,
    CMDOSE,
    CMDOSU,
    CMDOSFRQ,
    CMROUTE,
    CMSTDTC,
    CMENDTC,
    CMSTDY,
    CMENDY,
    EPOCH,
    CMCLAS,
    CMINDC,
    CMONGO
  )

# -- END CM --

# ==============================================================================
# End of Program
# ==============================================================================


# -- BEGIN SUPPCM -- #

# Merge CM with raw_cm to get qualifier variables
cm_with_qualifiers <- cm %>%
  select(STUDYID, USUBJID, CMSEQ) %>%
  left_join(
    raw_cm %>% select(USUBJID, CMSEQ, CMINDOTH, CMPREVFL),
    by = c("USUBJID", "CMSEQ")
  )

# Pivot qualifier variables into QNAM/QVAL structure
suppcm <- cm_with_qualifiers %>%
  pivot_longer(
    cols = c(CMINDOTH, CMPREVFL),
    names_to = "QNAM",
    values_to = "QVAL"
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  mutate(
    RDOMAIN = "CM",
    IDVAR = "CMSEQ",
    IDVARVAL = as.character(CMSEQ),
    QLABEL = case_when(
      QNAM == "CMINDOTH" ~ "Other Indication",
      QNAM == "CMPREVFL" ~ "Prior Medication?: Yes No",
      TRUE ~ NA_character_
    ),
    QVAL = as.character(QVAL),
    QORIG = "CRF",
    QEVAL = NA_character_,
    CMINDOTH = NA_character_,
    CMPREVFL = NA_character_
  ) %>%
  arrange(USUBJID, IDVARVAL, QNAM) %>%
  select(STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL, QORIG, QEVAL, CMINDOTH, CMPREVFL)

# -- END SUPPCM -- #

# -- Verification -- #
# glimpse(cm)
# table(cm$DOMAIN)

# End of cm.R
