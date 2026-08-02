# ********************************************************************
# Program:    tu.R
# Domain:     TU (Findings About Events)
# Purpose:    Create SDTM TU domain data frame
# Variables:  20
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     tu data frame (TU domain dataset)
#
# Variables:  STUDYID, TUSEQ, USUBJID, DOMAIN, TUTESTCD, TUTEST, TUCAT, TUORRES
#             ...
# ********************************************************************

# ==============================================================================
# Program: TU Domain - Tumor/Response Assessments
# Description: Create SDTM TU domain from raw tumor assessment data
# CDISC SDTM Version: 3.4
# ==============================================================================

library(dplyr)

# -- BEGIN TU -- #

# Read source data (raw_tu and dm already loaded in session)

# Create TU domain
tu <- raw_tu %>%
  # Join with DM to get USUBJID and RFSTDTC
  left_join(
    dm %>% select(SUBJID, USUBJID, RFSTDTC, STUDYID),
    by = "SUBJID"
  ) %>%
  # Assign domain and derive variables
  mutate(
    STUDYID = STUDYID,
    DOMAIN = "TU",
    TUTESTCD = TUTESTCD,
    TUTEST = TUTEST,
    TUCAT = TUCAT,
    TUORRES = TUORRES,
    
    # Derive character result in standard format
    TUSTRESC = case_when(
      !is.na(TUORRES) ~ as.character(TUORRES),
      TRUE ~ NA_character_
    ),
    
    # Derive numeric result
    TUSTRESN = case_when(
      !is.na(TUORRES) & grepl("^-?[0-9]+(\\.[0-9]+)?$", trimws(as.character(TUORRES))) ~ as.numeric(TUORRES),
      TRUE ~ NA_real_
    ),
    
    TUSTRESU = TUSTRESU,
    TUEVAL = TUEVAL,
    TULNKID = TULNKID,
    VISITNUM = VISITNUM,
    VISIT = VISIT,
    TUDTC = TUDTC,
    
    # Derive study day
    TUDY = case_when(
      !is.na(TUDTC) & !is.na(RFSTDTC) ~ as.numeric(
        as.Date(substr(TUDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))
      ) + if_else(
        as.Date(substr(TUDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)),
        1L,
        0L
      ),
      TRUE ~ NA_real_
    ),
    
    TULAT = TULAT,
    TULOC = TULOC,
    TUMETHOD = TUMETHOD
  ) %>%
  # Derive sequence number within subject
  group_by(USUBJID) %>%
  arrange(USUBJID, TUTESTCD, VISITNUM, TUDTC) %>%
  mutate(TUSEQ = row_number()) %>%
  ungroup() %>%
  # Sort final dataset
  arrange(STUDYID, USUBJID, TUSEQ) %>%
  # Select only specification variables in order
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    TUSEQ,
    TUTESTCD,
    TUTEST,
    TUCAT,
    TUORRES,
    TUSTRESC,
    TUSTRESN,
    TUSTRESU,
    TUEVAL,
    TULNKID,
    VISITNUM,
    VISIT,
    TUDTC,
    TUDY,
    TULAT,
    TULOC,
    TUMETHOD
  )

# -- END TU -- #

# -- Verification -- #
# glimpse(tu)
# table(tu$DOMAIN)

# End of tu.R
