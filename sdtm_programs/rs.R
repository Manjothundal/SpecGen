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

# -- BEGIN RS -- #

library(dplyr)

# SDTM RS Domain: Findings About Events (Tumor/Response Assessments)
# Production-quality script

# Variable labels (for documentation):
# STUDYID:  Study Identifier
# DOMAIN:   Domain Abbreviation
# USUBJID:  Unique Subject Identifier
# RSSEQ:    Sequence Number
# RSTESTCD: Short Name of Assessment
# RSTEST:   Name of Assessment
# RSCAT:    Category for Assessment
# RSORRES:  Result or Finding in Original Units
# RSSTRESC: Character Result in Std Format
# RSSTRESN: Numeric Result in Standard Units
# RSSTRESU: Standard Units
# RSEVAL:   Evaluator
# RSLNKID:  Link ID
# VISITNUM: Visit Number
# VISIT:    Visit Name
# RSDTC:    Date/Time of Collection
# RSDY:     Study Day of Collection

# Merge raw_rs with dm to get USUBJID and RFSTDTC
rs <- raw_rs %>%
  left_join(dm %>% select(STUDYID, SUBJID, USUBJID, RFSTDTC),
            by = c("STUDYID", "SUBJID")) %>%
  
  # Set domain
  mutate(DOMAIN = "RS") %>%
  
  # Map test codes and test names
  mutate(
    RSTESTCD = case_when(
      !is.na(OVRLRESP) ~ "OVRLRESP",
      !is.na(TUMORSUM) ~ "TUMORSUM",
      !is.na(NONTLRESP) ~ "NONTLRESP",
      !is.na(NEWLES) ~ "NEWLES",
      !is.na(RSTESTCD) ~ RSTESTCD,
      TRUE ~ NA_character_
    ),
    RSTEST = case_when(
      RSTESTCD == "OVRLRESP" ~ "Overall Response",
      RSTESTCD == "TUMORSUM" ~ "Sum of Target Lesion Diameters",
      RSTESTCD == "NONTLRESP" ~ "Non-Target Lesion Response",
      RSTESTCD == "NEWLES" ~ "New Lesions",
      !is.na(RSTEST) ~ RSTEST,
      TRUE ~ NA_character_
    )
  ) %>%
  
  # Map original results
  mutate(
    RSORRES = case_when(
      RSTESTCD == "OVRLRESP" ~ OVRLRESP,
      RSTESTCD == "TUMORSUM" ~ as.character(TUMORSUM),
      RSTESTCD == "NONTLRESP" ~ NONTLRESP,
      RSTESTCD == "NEWLES" ~ NEWLES,
      !is.na(RSORRES) ~ RSORRES,
      TRUE ~ NA_character_
    )
  ) %>%
  
  # Derive standardized character result
  mutate(
    RSSTRESC = case_when(
      RSTESTCD == "OVRLRESP" ~ toupper(RSORRES),
      RSTESTCD == "NONTLRESP" ~ toupper(RSORRES),
      RSTESTCD == "NEWLES" ~ toupper(RSORRES),
      !is.na(RSORRES) ~ RSORRES,
      TRUE ~ NA_character_
    )
  ) %>%
  
  # Derive numeric result
  mutate(
    RSSTRESN = case_when(
      RSTESTCD == "TUMORSUM" ~ as.numeric(RSORRES),
      TRUE ~ NA_real_
    )
  ) %>%
  
  # Set standard units
  mutate(
    RSSTRESU = case_when(
      RSTESTCD == "TUMORSUM" ~ "mm",
      TRUE ~ NA_character_
    )
  ) %>%
  
  # Map category (assessment criteria)
  mutate(
    RSCAT = if_else(!is.na(RSCAT), RSCAT, "RECIST 1.1")
  ) %>%
  
  # Map evaluator
  mutate(
    RSEVAL = case_when(
      !is.na(RSEVAL) ~ RSEVAL,
      toupper(EVAL) == "INVESTIGATOR" ~ "INVESTIGATOR",
      toupper(EVAL) == "INDEPENDENT" ~ "INDEPENDENT ASSESSOR",
      toupper(EVAL) == "INDEPENDENT ASSESSOR" ~ "INDEPENDENT ASSESSOR",
      TRUE ~ "INVESTIGATOR"
    )
  ) %>%
  
  # Map link ID
  mutate(
    RSLNKID = if_else(!is.na(RSLNKID), RSLNKID, 
                      if_else(!is.na(LNKID), LNKID, NA_character_))
  ) %>%
  
  # Map visit information
  mutate(
    VISITNUM = if_else(!is.na(VISITNUM), VISITNUM, as.numeric(VISITN)),
    VISIT = if_else(!is.na(VISIT), VISIT, VISITNAM)
  ) %>%
  
  # Map date/time of collection
  mutate(
    RSDTC = case_when(
      !is.na(RSDTC) ~ RSDTC,
      !is.na(RSDTM) ~ RSDTM,
      !is.na(RSDAT) ~ RSDAT,
      TRUE ~ NA_character_
    )
  ) %>%
  
  # Derive study day
  mutate(
    RSDY = case_when(
      !is.na(RSDTC) & !is.na(RFSTDTC) ~ 
        as.numeric(as.Date(substr(RSDTC, 1, 10)) - as.Date(substr(RFSTDTC, 1, 10))) + 
        if_else(as.Date(substr(RSDTC, 1, 10)) >= as.Date(substr(RFSTDTC, 1, 10)), 1, 0),
      TRUE ~ NA_real_
    )
  ) %>%
  
  # Derive sequence number within subject
  group_by(USUBJID) %>%
  arrange(USUBJID, VISITNUM, RSTESTCD, RSDTC) %>%
  mutate(RSSEQ = row_number()) %>%
  ungroup() %>%
  
  # Final sort
  arrange(STUDYID, USUBJID, RSSEQ) %>%
  
  # Select only specification variables in order
  select(
    STUDYID,
    RSSEQ,
    USUBJID,
    DOMAIN,
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

# Define qualifier variables metadata
qualifiers <- tribble(
  ~qnam,        ~qlabel,                                      ~qorig, ~qeval,
  "RSBORRESP",  "Best Overall Response: CR PR SD PD",         "CRF",  NA_character_,
  "RSCONFDTC",  "Date of Confirmation",                       "CRF",  NA_character_,
  "RSCONFYN",   "Confirmed Response?: Yes No",                "CRF",  NA_character_
)

# Merge RS domain with raw data to get qualifier variables
rs_with_qual <- rs %>%
  select(STUDYID, USUBJID, RSSEQ) %>%
  left_join(
    raw_rs %>%
      select(STUDYID, USUBJID, any_of(qualifiers$qnam)),
    by = c("STUDYID", "USUBJID")
  )

# Pivot qualifier variables to long format
supprs <- rs_with_qual %>%
  pivot_longer(
    cols = any_of(qualifiers$qnam),
    names_to = "QNAM",
    values_to = "QVAL",
    values_transform = as.character
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  left_join(qualifiers, by = c("QNAM" = "qnam")) %>%
  mutate(
    RDOMAIN = "RS",
    IDVAR = "RSSEQ",
    IDVARVAL = as.character(RSSEQ),
    QNAM = QNAM,
    QLABEL = qlabel,
    QVAL = QVAL,
    QORIG = qorig,
    QEVAL = qeval,
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
