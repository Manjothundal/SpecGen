# ********************************************************************
# Program:    vs.R
# Domain:     VS (Findings)
# Purpose:    Create SDTM VS domain data frame
# Variables:  19
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     vs data frame (VS domain dataset)
#
# Variables:  STUDYID, VSSEQ, USUBJID, DOMAIN, VSTESTCD, VSTEST, VSCAT, VSORRES
#             ...
# ********************************************************************

# ==============================================================================
# SDTM VS Domain - Vital Signs
# ==============================================================================
# Variable labels (R does not support SAS-style labels/lengths; listed here for reference):
# STUDYID:  Study Identifier
# VSSEQ:    Sequence Number
# USUBJID:  Unique Subject Identifier
# DOMAIN:   Domain Abbreviation
# VSTESTCD: Short Name of Measurement
# VSTEST:   Name of Measurement
# VSCAT:    Category for Findings
# VSORRES:  Result or Finding in Original Units
# VSORRESU: Original Units
# VSSTRESC: Character Result in Std Format
# VSSTRESN: Numeric Result in Standard Units
# VSSTRESU: Standard Units
# VSSTAT:   Completion Status
# VSREASND: Reason Not Performed
# VISITNUM: Visit Number
# VISIT:    Visit Name
# VSDTC:    Date/Time of Collection
# VSDY:     Study Day of Collection
# VSPOS:    Position: Sitting Standing Supine
# ==============================================================================

library(dplyr)
library(tidyr)

# -- BEGIN VS -- #

# ==============================================================================
# 1. Prepare DM for merging (get USUBJID and RFSTDTC)
# ==============================================================================

dm_subset <- dm %>%
  select(STUDYID, USUBJID, RFSTDTC)

# ==============================================================================
# 2. Derive USUBJID
#    Assumes raw_vs contains columns: STUDYID, SITEID, SUBJID, VISIT, 
#    VISITNUM, VSDTC, VSTESTCD, VSORRES, VSORRESU, VSPOS, VSREASND
# ==============================================================================

vs_base <- raw_vs %>%
  mutate(
    USUBJID = paste(STUDYID, SITEID, SUBJID, sep = "-")
  )

# ==============================================================================
# 3. Map test codes and test names
#    Create standardized VSTESTCD and VSTEST mappings
# ==============================================================================

test_mapping <- tribble(
  ~VSTESTCD, ~VSTEST,           ~VSSTRESU,
  "SYSBP",   "Systolic Blood Pressure",   "mmHg",
  "DIABP",   "Diastolic Blood Pressure",  "mmHg",
  "PULSE",   "Pulse Rate",                "beats/min",
  "TEMP",    "Temperature",               "C",
  "RESP",    "Respiratory Rate",          "breaths/min",
  "WEIGHT",  "Weight",                    "kg",
  "HEIGHT",  "Height",                    "cm"
)

vs_mapped <- vs_base %>%
  left_join(test_mapping, by = "VSTESTCD") %>%
  filter(!is.na(VSTEST))  # Remove unmapped tests

# ==============================================================================
# 4. Set DOMAIN and VSCAT
# ==============================================================================

vs_mapped <- vs_mapped %>%
  mutate(
    DOMAIN = "VS",
    VSCAT = "VITAL SIGNS"
  )

# ==============================================================================
# 5. Derive VSORRES, VSSTRESC, VSSTRESN, VSSTAT
#    Handle NOT DONE cases
# ==============================================================================

vs_mapped <- vs_mapped %>%
  mutate(
    # Original result as character
    VSORRES = as.character(VSORRES),
    
    # Determine completion status
    VSSTAT = case_when(
      is.na(VSORRES) | trimws(as.character(VSORRES)) == "" ~ "NOT DONE",
      TRUE ~ NA_character_
    ),
    
    # Standardized character result
    VSSTRESC = case_when(
      VSSTAT == "NOT DONE" ~ NA_character_,
      TRUE ~ as.character(VSORRES)
    ),
    
    # Numeric result in standard units
    VSSTRESN = case_when(
      VSSTAT == "NOT DONE" ~ NA_real_,
      TRUE ~ as.numeric(VSORRES)
    )
  )

# ==============================================================================
# 6. Handle reason not done
#    Use VSREASND from raw_vs; set to NA if VSSTAT is not "NOT DONE"
# ==============================================================================

vs_mapped <- vs_mapped %>%
  mutate(
    VSREASND = case_when(
      VSSTAT == "NOT DONE" ~ as.character(VSREASND),
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# 7. Merge with DM to get RFSTDTC for study day calculation
# ==============================================================================

vs_merged <- vs_mapped %>%
  left_join(dm_subset, by = c("STUDYID", "USUBJID"))

# ==============================================================================
# 8. Derive VSDY (Study Day)
#    VSDY = Date of Collection - RFSTDTC + 1 (if on or after), or 
#           Date of Collection - RFSTDTC (if before)
# ==============================================================================

vs_merged <- vs_merged %>%
  mutate(
    VSDY = case_when(
      is.na(VSDTC) | is.na(RFSTDTC) ~ NA_real_,
      TRUE ~ {
        vs_date <- as.Date(substr(VSDTC, 1, 10))
        rf_date <- as.Date(substr(RFSTDTC, 1, 10))
        diff <- as.numeric(vs_date - rf_date)
        if_else(diff >= 0, diff + 1, diff)
      }
    )
  )

# ==============================================================================
# 9. Derive VSSEQ within each subject
# ==============================================================================

vs_seq <- vs_merged %>%
  arrange(STUDYID, USUBJID, VSTESTCD, VISITNUM, VSDTC) %>%
  group_by(USUBJID) %>%
  mutate(VSSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# 10. Select and order final variables per SDTM spec
# ==============================================================================

vs <- vs_seq %>%
  select(
    STUDYID,
    VSSEQ,
    USUBJID,
    DOMAIN,
    VSTESTCD,
    VSTEST,
    VSCAT,
    VSORRES,
    VSORRESU,
    VSSTRESC,
    VSSTRESN,
    VSSTRESU,
    VSSTAT,
    VSREASND,
    VISITNUM,
    VISIT,
    VSDTC,
    VSDY,
    VSPOS
  ) %>%
  arrange(STUDYID, USUBJID, VSTESTCD, VISITNUM, VSDTC)

# -- END VS -- #


# -- BEGIN SUPPVS -- #


# Define qualifier variables metadata
qualifier_meta <- tibble::tribble(
  ~qnam,      ~qlabel,                              ~qorig,  ~qeval,
  "VSCLSIG",  "Clinically Significant?: Yes No",    "CRF",   NA_character_,
  "VSFAST",   "Fasting?: Yes No",                   "CRF",   NA_character_,
  "VSLOC",    "Location of Measurement",            "CRF",   NA_character_
)

# Get parent domain identifiers and qualifier source values
suppvs_source <- raw_vs %>%
  inner_join(
    vs %>% select(STUDYID, USUBJID, VSSEQ),
    by = c("STUDYID", "USUBJID", "VSSEQ")
  ) %>%
  select(STUDYID, USUBJID, VSSEQ, VSCLSIG, VSFAST, VSLOC)

# Pivot qualifier columns to QNAM/QVAL structure
suppvs <- suppvs_source %>%
  pivot_longer(
    cols = c(VSCLSIG, VSFAST, VSLOC),
    names_to = "QNAM",
    values_to = "QVAL"
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  left_join(
    qualifier_meta,
    by = c("QNAM" = "qnam")
  ) %>%
  mutate(
    RDOMAIN = "VS",
    IDVAR = "VSSEQ",
    IDVARVAL = as.character(VSSEQ),
    QVAL = as.character(QVAL),
    QLABEL = qlabel,
    QORIG = qorig,
    QEVAL = qeval
  ) %>%
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
    QEVAL
  ) %>%
  arrange(STUDYID, RDOMAIN, USUBJID, IDVARVAL, QNAM)

# -- END SUPPVS -- #

# -- Verification -- #
# glimpse(vs)
# table(vs$DOMAIN)

# End of vs.R
