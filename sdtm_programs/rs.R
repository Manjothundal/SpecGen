# ********************************************************************
# Program:    rs.R
# Domain:     RS (Findings About Events)
# Purpose:    Create SDTM RS domain data frame
# Variables:  17
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     rs data frame (RS domain dataset)
#
# Variables:  STUDYID, RSSEQ, USUBJID, DOMAIN, RSTESTCD, RSTEST, RSCAT, RSORRES
#             ...
# ********************************************************************

# ==============================================================================
# Program: RS Domain (Tumor/Response Assessments)
# SDTM Findings About Events Class
# ==============================================================================

library(dplyr)

# -- BEGIN RS -- #

rs <- raw_rs %>%
  # Join with DM domain to get USUBJID, STUDYID, and RFSTDTC
  left_join(
    dm %>% select(SUBJID, USUBJID, STUDYID, RFSTDTC),
    by = "SUBJID"
  ) %>%
  # Set Domain
  mutate(DOMAIN = "RS") %>%
  # Map RSTESTCD and RSTEST
  mutate(
    RSTESTCD = case_when(
      TEST == "OVERALL RESPONSE" ~ "OVRLRESP",
      TEST == "OVERALL RESPONSE BY RECIST" ~ "OVRLRESP",
      TEST == "BEST OVERALL RESPONSE" ~ "BESTRESP",
      TEST == "TARGET LESION RESPONSE" ~ "TRGRESP",
      TEST == "NON-TARGET LESION RESPONSE" ~ "NTRGRESP",
      TEST == "NEW LESION" ~ "NEWLES",
      TRUE ~ as.character(TESTCD)
    ),
    RSTEST = case_when(
      TEST == "OVERALL RESPONSE" ~ "Overall Response",
      TEST == "OVERALL RESPONSE BY RECIST" ~ "Overall Response",
      TEST == "BEST OVERALL RESPONSE" ~ "Best Overall Response",
      TEST == "TARGET LESION RESPONSE" ~ "Target Lesion Response",
      TEST == "NON-TARGET LESION RESPONSE" ~ "Non-Target Lesion Response",
      TEST == "NEW LESION" ~ "New Lesion",
      TRUE ~ as.character(TEST)
    )
  ) %>%
  # Map RSCAT (Category for Assessment)
  mutate(
    RSCAT = case_when(
      !is.na(CAT) ~ as.character(CAT),
      !is.na(CRITERIA) ~ as.character(CRITERIA),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map RSORRES (Result in Original Units)
  mutate(RSORRES = as.character(ORRES)) %>%
  # Derive RSSTRESC (Character Result in Standard Format)
  mutate(
    RSSTRESC = case_when(
      toupper(RSORRES) == "CR" ~ "CR",
      toupper(RSORRES) == "COMPLETE RESPONSE" ~ "CR",
      toupper(RSORRES) == "PR" ~ "PR",
      toupper(RSORRES) == "PARTIAL RESPONSE" ~ "PR",
      toupper(RSORRES) == "SD" ~ "SD",
      toupper(RSORRES) == "STABLE DISEASE" ~ "SD",
      toupper(RSORRES) == "PD" ~ "PD",
      toupper(RSORRES) == "PROGRESSIVE DISEASE" ~ "PD",
      toupper(RSORRES) == "NE" ~ "NE",
      toupper(RSORRES) == "NOT EVALUABLE" ~ "NE",
      toupper(RSORRES) == "NOT DONE" ~ "ND",
      toupper(RSORRES) == "ND" ~ "ND",
      toupper(RSORRES) == "YES" ~ "YES",
      toupper(RSORRES) == "NO" ~ "NO",
      toupper(RSORRES) == "PRESENT" ~ "PRESENT",
      toupper(RSORRES) == "ABSENT" ~ "ABSENT",
      toupper(RSORRES) == "NON-CR/NON-PD" ~ "NON-CR/NON-PD",
      toupper(RSORRES) == "NON-PD" ~ "NON-PD",
      !is.na(RSORRES) ~ toupper(RSORRES),
      TRUE ~ NA_character_
    )
  ) %>%
  # Derive RSSTRESN (Numeric Result - not typically used for RS)
  mutate(RSSTRESN = NA_real_) %>%
  # Map RSSTRESU (Standard Units - typically not applicable for RS)
  mutate(RSSTRESU = NA_character_) %>%
  # Map RSEVAL (Evaluator)
  mutate(
    RSEVAL = case_when(
      toupper(EVAL) == "INVESTIGATOR" ~ "INVESTIGATOR",
      toupper(EVAL) == "INV" ~ "INVESTIGATOR",
      toupper(EVAL) == "INDEPENDENT ASSESSOR" ~ "INDEPENDENT ASSESSOR",
      toupper(EVAL) == "INDEPENDENT" ~ "INDEPENDENT ASSESSOR",
      toupper(EVAL) == "IRC" ~ "INDEPENDENT ASSESSOR",
      !is.na(EVAL) ~ as.character(EVAL),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map RSLNKID (Link ID for TU/TR/RS linkage)
  mutate(
    RSLNKID = case_when(
      !is.na(LNKID) ~ as.character(LNKID),
      !is.na(LINKID) ~ as.character(LINKID),
      TRUE ~ NA_character_
    )
  ) %>%
  # Map VISITNUM and VISIT
  mutate(
    VISITNUM = as.numeric(VISITNUM),
    VISIT = as.character(VISIT)
  ) %>%
  # Map RSDTC (Date/Time of Collection)
  mutate(RSDTC = as.character(DTC)) %>%
  # Derive RSDY (Study Day relative to RFSTDTC)
  mutate(
    RSDY = case_when(
      !is.na(RSDTC) & !is.na(RFSTDTC) ~ as.numeric(
        as.Date(substr(RSDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))
      ) + if_else(
        as.Date(substr(RSDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)),
        1,
        0
      ),
      TRUE ~ NA_real_
    )
  ) %>%
  # Derive RSSEQ within each subject
  arrange(STUDYID, USUBJID, RSTESTCD, VISITNUM, RSDTC) %>%
  group_by(USUBJID) %>%
  mutate(RSSEQ = row_number()) %>%
  ungroup() %>%
  # Sort final dataset
  arrange(STUDYID, USUBJID, RSSEQ) %>%
  # Select only SDTM variables in specification order
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    RSSEQ,
    RSTESTCD,
    RSTEST,
    RSCAT,
    RSORRES,
    RSSTRESC,
    RSSTRESN,
    RSSTRESU,
    RSEVAL,
    RSLNKID,
    VISITNUM,
    VISIT,
    RSDTC,
    RSDY
  )

# -- END RS -- #

# -- BEGIN SUPPRS -- #

# Create supplemental qualifiers for RS domain

# Merge raw_rs with rs to get RSSEQ
rs_with_seq <- raw_rs %>%
  inner_join(
    rs %>% select(STUDYID, USUBJID, RSSEQ, any_of(c("RSTESTCD", "RSTEST", "RSDTC", "VISITNUM", "VISIT"))),
    by = c("STUDYID", "USUBJID", intersect(names(raw_rs), c("RSTESTCD", "RSTEST", "RSDTC", "VISITNUM", "VISIT")))
  )

# Define qualifier metadata
qual_metadata <- tribble(
  ~QNAM,        ~QLABEL,
  "RSBORRESP",  "Best Overall Response: CR PR SD PD",
  "RSCONFDTC",  "Date of Confirmation",
  "RSCONFYN",   "Confirmed Response?: Yes No"
)

# Select relevant columns and prepare for pivoting
supprs_wide <- rs_with_seq %>%
  select(
    STUDYID,
    USUBJID,
    RSSEQ,
    any_of(c("RSBORRESP", "RSCONFDTC", "RSCONFYN"))
  ) %>%
  distinct()

# Pivot longer to create QNAM/QVAL pairs
supprs <- supprs_wide %>%
  pivot_longer(
    cols = any_of(c("RSBORRESP", "RSCONFDTC", "RSCONFYN")),
    names_to = "QNAM",
    values_to = "QVAL",
    values_transform = as.character
  ) %>%
  filter(!is.na(QVAL)) %>%
  left_join(qual_metadata, by = "QNAM") %>%
  mutate(
    RDOMAIN = "RS",
    IDVAR = "RSSEQ",
    IDVARVAL = as.character(RSSEQ),
    QORIG = "CRF",
    QEVAL = NA_character_,
    RSBORRESP = NA_character_,
    RSCONFDTC = NA_character_,
    RSCONFYN = NA_character_
  ) %>%
  arrange(STUDYID, RDOMAIN, USUBJID, IDVARVAL, QNAM) %>%
  select(
    STUDYID,
    RDOMAIN,
    USUBJID,
    IDVAR,
    IDVARVAL,
    QNAM,
    QLABEL,
    QVAL,
    QORIG,
    QEVAL,
    RSBORRESP,
    RSCONFDTC,
    RSCONFYN
  )

# -- END SUPPRS -- #

# -- Verification -- #
# glimpse(rs)
# table(rs$DOMAIN)

# End of rs.R
