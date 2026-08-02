# ********************************************************************
# Program:    tr.R
# Domain:     TR (Findings About Events)
# Purpose:    Create SDTM TR domain data frame
# Variables:  17
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     tr data frame (TR domain dataset)
#
# Variables:  STUDYID, TRSEQ, USUBJID, DOMAIN, TRTESTCD, TRTEST, TRCAT, TRORRES
#             ...
# ********************************************************************

# ==============================================================================
# SDTM TR Domain: Tumor/Response Assessments
# ==============================================================================
# Variable Labels (per SDTM spec):
# STUDYID:  Study Identifier
# TRSEQ:    Sequence Number
# USUBJID:  Unique Subject Identifier
# DOMAIN:   Domain Abbreviation
# TRTESTCD: Short Name of Assessment
# TRTEST:   Name of Assessment
# TRCAT:    Category for Assessment
# TRORRES:  Result or Finding in Original Units
# TRSTRESC: Character Result in Std Format
# TRSTRESN: Numeric Result in Standard Units
# TRSTRESU: Standard Units
# TREVAL:   Evaluator
# TRLNKID:  Link ID
# VISITNUM: Visit Number
# VISIT:    Visit Name
# TRDTC:    Date/Time of Collection
# TRDY:     Study Day of Collection
# ==============================================================================

library(dplyr)

# -- BEGIN TR -- #

tr <- raw_tr %>%
  # Join with DM to get USUBJID and RFSTDTC
  left_join(
    dm %>% select(STUDYID, SUBJID, USUBJID, RFSTDTC),
    by = c("STUDYID", "SUBJID")
  ) %>%
  # Set domain
  mutate(DOMAIN = "TR") %>%
  # Map test codes and names
  mutate(
    TRTESTCD = case_when(
      TEST == "OVERALL RESPONSE" ~ "OVRLRESP",
      TEST == "TARGET RESPONSE" ~ "TGRESP",
      TEST == "NON-TARGET RESPONSE" ~ "NTGRESP",
      TEST == "NEW LESION" ~ "NEWLES",
      TEST == "BEST OVERALL RESPONSE" ~ "BORRESP",
      !is.na(TESTCD) ~ as.character(TESTCD),
      TRUE ~ NA_character_
    ),
    TRTEST = case_when(
      TEST == "OVERALL RESPONSE" ~ "Overall Response",
      TEST == "TARGET RESPONSE" ~ "Target Response",
      TEST == "NON-TARGET RESPONSE" ~ "Non-Target Response",
      TEST == "NEW LESION" ~ "New Lesion",
      TEST == "BEST OVERALL RESPONSE" ~ "Best Overall Response",
      !is.na(TEST) ~ as.character(TEST),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map category
  mutate(
    TRCAT = case_when(
      !is.na(CAT) ~ as.character(CAT),
      !is.na(CRITERIA) ~ as.character(CRITERIA),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map original results
  mutate(TRORRES = if_else(!is.na(ORRES), as.character(ORRES), NA_character_)) %>%
  # Map standardized character result
  mutate(
    TRSTRESC = case_when(
      !is.na(STRESC) ~ as.character(STRESC),
      !is.na(ORRES) ~ as.character(ORRES),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map standardized numeric result
  mutate(
    TRSTRESN = case_when(
      !is.na(STRESN) ~ as.numeric(STRESN),
      !is.na(RESN) ~ as.numeric(RESN),
      TRUE ~ NA_real_
    )
  ) %>%
  # Map standard units
  mutate(
    TRSTRESU = case_when(
      !is.na(STRESU) ~ as.character(STRESU),
      !is.na(UNIT) ~ as.character(UNIT),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map evaluator
  mutate(
    TREVAL = case_when(
      toupper(EVAL) == "INV" ~ "INVESTIGATOR",
      toupper(EVAL) == "INVESTIGATOR" ~ "INVESTIGATOR",
      toupper(EVAL) == "IRC" ~ "INDEPENDENT ASSESSOR",
      toupper(EVAL) == "INDEPENDENT" ~ "INDEPENDENT ASSESSOR",
      toupper(EVAL) == "INDEPENDENT ASSESSOR" ~ "INDEPENDENT ASSESSOR",
      !is.na(EVAL) ~ as.character(EVAL),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map link ID
  mutate(TRLNKID = if_else(!is.na(LNKID), as.character(LNKID), NA_character_)) %>%
  # Map visit variables
  mutate(
    VISITNUM = if_else(!is.na(VISITNUM), as.numeric(VISITNUM), NA_real_),
    VISIT = if_else(!is.na(VISIT), as.character(VISIT), NA_character_)
  ) %>%
  # Map date/time of collection
  mutate(TRDTC = if_else(!is.na(DTC), as.character(DTC), NA_character_)) %>%
  # Derive study day
  mutate(
    TRDY = case_when(
      !is.na(TRDTC) & !is.na(RFSTDTC) ~ as.numeric(
        as.Date(substr(TRDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))
      ) + if_else(
        as.Date(substr(TRDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 
        1, 
        0
      ),
      TRUE ~ NA_real_
    )
  ) %>%
  # Derive sequence number
  arrange(STUDYID, USUBJID, TRTESTCD, VISITNUM, TRDTC) %>%
  group_by(USUBJID) %>%
  mutate(TRSEQ = row_number()) %>%
  ungroup() %>%
  # Sort final dataset
  arrange(STUDYID, USUBJID, TRSEQ) %>%
  # Select and order variables per SDTM spec
  select(
    STUDYID,
    TRSEQ,
    USUBJID,
    DOMAIN,
    TRTESTCD,
    TRTEST,
    TRCAT,
    TRORRES,
    TRSTRESC,
    TRSTRESN,
    TRSTRESU,
    TREVAL,
    TRLNKID,
    VISITNUM,
    VISIT,
    TRDTC,
    TRDY
  )

# -- END TR -- #

# -- Verification -- #
# glimpse(tr)
# table(tr$DOMAIN)

# End of tr.R
