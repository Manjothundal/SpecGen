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

library(dplyr)

# -- BEGIN TR -- #

# Derive TR domain (Tumor/Lesion Results)
tr <- raw_tr %>%
  # Join with DM to get USUBJID, RFSTDTC, and STUDYID
  left_join(
    dm %>% select(SUBJID, USUBJID, STUDYID, RFSTDTC),
    by = "SUBJID"
  ) %>%
  # Set DOMAIN
  mutate(
    DOMAIN = "TR"
  ) %>%
  # Map assessments
  mutate(
    TRTESTCD = if (exists("TRTESTCD", where = .)) TRTESTCD else NA_character_,
    TRTEST = if (exists("TRTEST", where = .)) TRTEST else NA_character_,
    TRCAT = if (exists("TRCAT", where = .)) TRCAT else NA_character_,
    TRORRES = if (exists("TRORRES", where = .)) TRORRES else NA_character_,
    TRSTRESN = if (exists("TRSTRESN", where = .)) TRSTRESN else NA_real_,
    TRSTRESC = case_when(
      !is.na(TRSTRESN) ~ as.character(TRSTRESN),
      !is.na(TRORRES) ~ TRORRES,
      TRUE ~ NA_character_
    ),
    TRSTRESU = if (exists("TRSTRESU", where = .)) TRSTRESU else NA_character_,
    TREVAL = if (exists("TREVAL", where = .)) TREVAL else NA_character_,
    TRLNKID = if (exists("TRLNKID", where = .)) TRLNKID else NA_character_,
    VISITNUM = if (exists("VISITNUM", where = .)) as.numeric(VISITNUM) else NA_real_,
    VISIT = if (exists("VISIT", where = .)) VISIT else NA_character_,
    TRDTC = if (exists("TRDTC", where = .)) TRDTC else NA_character_
  ) %>%
  # Derive TRDY (study day relative to RFSTDTC)
  mutate(
    TRDY = case_when(
      !is.na(TRDTC) & !is.na(RFSTDTC) & nchar(TRDTC) >= 10 & nchar(RFSTDTC) >= 10 ~ {
        days_diff <- as.numeric(as.Date(substr(TRDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10)))
        if_else(days_diff >= 0, days_diff + 1, days_diff)
      },
      TRUE ~ NA_real_
    )
  ) %>%
  # Derive TRSEQ as sequence number within each subject
  group_by(USUBJID) %>%
  arrange(USUBJID, VISITNUM, TRDTC, TRTESTCD, TRLNKID) %>%
  mutate(TRSEQ = row_number()) %>%
  ungroup() %>%
  # Sort final dataset
  arrange(STUDYID, USUBJID, TRSEQ) %>%
  # Select only specification variables in order
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
