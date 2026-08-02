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

library(dplyr)

# -- BEGIN TU -- #

# Tumor/Lesion Identification Domain (TU)
# Findings About Events class - tumor/response assessments

tu <- raw_tu %>%
  # Join with DM to get USUBJID and RFSTDTC
  left_join(
    dm %>% select(SUBJID, USUBJID, RFSTDTC, STUDYID),
    by = c("SUBJID", "STUDYID")
  ) %>%
  # Set DOMAIN
  mutate(DOMAIN = "TU") %>%
  # Map assessment test codes and test names
  mutate(
    TUTESTCD = case_when(
      !is.na(TUORRES_DIAM) ~ "DIAMETER",
      !is.na(TUORRES_LDIAX) ~ "LDIAX",
      !is.na(TUORRES_PDIAX) ~ "PDIAX",
      !is.na(TUORRES_SADIAM) ~ "SADIAM",
      TRUE ~ TUTESTCD
    ),
    TUTEST = case_when(
      TUTESTCD == "DIAMETER" ~ "Diameter",
      TUTESTCD == "LDIAX" ~ "Longest Diameter",
      TUTESTCD == "PDIAX" ~ "Perpendicular Diameter",
      TUTESTCD == "SADIAM" ~ "Sum of Diameters",
      TRUE ~ TUTEST
    )
  ) %>%
  # Map TUORRES from source
  mutate(
    TUORRES = case_when(
      TUTESTCD == "DIAMETER" ~ as.character(TUORRES_DIAM),
      TUTESTCD == "LDIAX" ~ as.character(TUORRES_LDIAX),
      TUTESTCD == "PDIAX" ~ as.character(TUORRES_PDIAX),
      TUTESTCD == "SADIAM" ~ as.character(TUORRES_SADIAM),
      TRUE ~ TUORRES
    )
  ) %>%
  # Derive TUSTRESC (character result in standard format)
  mutate(
    TUSTRESC = TUORRES
  ) %>%
  # Derive TUSTRESN (numeric result)
  mutate(
    TUSTRESN = as.numeric(TUSTRESC)
  ) %>%
  # Assign TUSTRESU (standard units)
  mutate(
    TUSTRESU = case_when(
      TUTESTCD %in% c("DIAMETER", "LDIAX", "PDIAX", "SADIAM") ~ "mm",
      TRUE ~ TUSTRESU
    )
  ) %>%
  # Map TUEVAL (evaluator)
  mutate(
    TUEVAL = case_when(
      !is.na(EVALUATOR) & toupper(EVALUATOR) == "INV" ~ "INVESTIGATOR",
      !is.na(EVALUATOR) & toupper(EVALUATOR) == "IRC" ~ "INDEPENDENT ASSESSOR",
      !is.na(EVALUATOR) & toupper(EVALUATOR) == "INVESTIGATOR" ~ "INVESTIGATOR",
      !is.na(EVALUATOR) & toupper(EVALUATOR) == "INDEPENDENT ASSESSOR" ~ "INDEPENDENT ASSESSOR",
      TRUE ~ NA_character_
    )
  ) %>%
  # Map TULNKID (link ID for linking TU/TR/RS)
  mutate(
    TULNKID = if_else(!is.na(LNKID), as.character(LNKID), NA_character_)
  ) %>%
  # Map VISITNUM and VISIT
  mutate(
    VISITNUM = as.numeric(VISITNUM),
    VISIT = as.character(VISIT)
  ) %>%
  # Map TUDTC (date/time of collection)
  mutate(
    TUDTC = as.character(TUDTC)
  ) %>%
  # Derive TUDY (study day relative to RFSTDTC)
  mutate(
    TUDY = case_when(
      !is.na(TUDTC) & !is.na(RFSTDTC) ~ 
        as.numeric(as.Date(substr(TUDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 
        if_else(as.Date(substr(TUDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1, 0),
      TRUE ~ NA_real_
    )
  ) %>%
  # Map TUCAT (category for assessment)
  mutate(
    TUCAT = if_else(!is.na(TUCAT), as.character(TUCAT), "RECIST 1.1")
  ) %>%
  # Map TULAT (laterality)
  mutate(
    TULAT = if_else(!is.na(TULAT), as.character(TULAT), NA_character_)
  ) %>%
  # Map TULOC (tumor location)
  mutate(
    TULOC = if_else(!is.na(TULOC), as.character(TULOC), NA_character_)
  ) %>%
  # Map TUMETHOD (method of assessment)
  mutate(
    TUMETHOD = if_else(!is.na(TUMETHOD), as.character(TUMETHOD), NA_character_)
  ) %>%
  # Sort and derive TUSEQ (sequence number within subject)
  arrange(STUDYID, USUBJID, TUTESTCD, VISITNUM, TUDTC, TULNKID) %>%
  group_by(USUBJID) %>%
  mutate(TUSEQ = row_number()) %>%
  ungroup() %>%
  # Select only spec variables in order
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
