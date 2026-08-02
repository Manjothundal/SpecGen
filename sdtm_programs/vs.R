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
# Program:      vs.R
# Description:  Create SDTM VS (Vital Signs) domain
# Input:        raw_vs, dm (already in R session)
# Output:       vs
# ==============================================================================

library(dplyr)
library(tidyr)

# -- BEGIN VS -- #

# ==============================================================================
# Derive VS domain
# ==============================================================================

# ------------------------------------------------------------------------------
# Assume raw_vs is in wide format with columns:
# STUDYID, SITEID, SUBJID, VISITNUM, VISIT, VS_DATE, VSPOS,
# SYSBP, DIABP, HR, TEMP, RESP, WEIGHT, HEIGHT, etc.
# Each vital sign parameter is in a separate column
# If raw_vs is already vertical, skip pivot_longer and map directly
# ------------------------------------------------------------------------------

# Check if raw_vs needs to be pivoted (example assumes wide format)
# Pivot longer to get one row per test per timepoint per subject
vs_long <- raw_vs %>%
  pivot_longer(
    cols = matches("^(SYSBP|DIABP|HR|TEMP|RESP|WEIGHT|HEIGHT)$"),
    names_to = "VSTESTCD",
    values_to = "VSORRES_RAW",
    values_drop_na = FALSE
  )

# ------------------------------------------------------------------------------
# Derive USUBJID
# ------------------------------------------------------------------------------
vs1 <- vs_long %>%
  mutate(
    USUBJID = paste(STUDYID, SITEID, SUBJID, sep = "-")
  )

# ------------------------------------------------------------------------------
# Set DOMAIN
# ------------------------------------------------------------------------------
vs2 <- vs1 %>%
  mutate(DOMAIN = "VS")

# ------------------------------------------------------------------------------
# Map VSTESTCD to VSTEST (full test name)
# ------------------------------------------------------------------------------
vs3 <- vs2 %>%
  mutate(
    VSTEST = case_when(
      VSTESTCD == "SYSBP"  ~ "Systolic Blood Pressure",
      VSTESTCD == "DIABP"  ~ "Diastolic Blood Pressure",
      VSTESTCD == "HR"     ~ "Heart Rate",
      VSTESTCD == "TEMP"   ~ "Temperature",
      VSTESTCD == "RESP"   ~ "Respiratory Rate",
      VSTESTCD == "WEIGHT" ~ "Weight",
      VSTESTCD == "HEIGHT" ~ "Height",
      TRUE ~ as.character(VSTESTCD)
    )
  )

# ------------------------------------------------------------------------------
# Set VSCAT (Category for Findings)
# ------------------------------------------------------------------------------
vs4 <- vs3 %>%
  mutate(VSCAT = "VITAL SIGNS")

# ------------------------------------------------------------------------------
# Derive VSORRES (original result as character)
# ------------------------------------------------------------------------------
vs5 <- vs4 %>%
  mutate(VSORRES = as.character(VSORRES_RAW))

# ------------------------------------------------------------------------------
# Derive VSORRESU (original units)
# ------------------------------------------------------------------------------
vs6 <- vs5 %>%
  mutate(
    VSORRESU = case_when(
      VSTESTCD == "SYSBP"  ~ "mmHg",
      VSTESTCD == "DIABP"  ~ "mmHg",
      VSTESTCD == "HR"     ~ "beats/min",
      VSTESTCD == "TEMP"   ~ "C",
      VSTESTCD == "RESP"   ~ "breaths/min",
      VSTESTCD == "WEIGHT" ~ "kg",
      VSTESTCD == "HEIGHT" ~ "cm",
      TRUE ~ NA_character_
    )
  )

# ------------------------------------------------------------------------------
# Derive VSSTRESC (standardized character result)
# ------------------------------------------------------------------------------
vs7 <- vs6 %>%
  mutate(VSSTRESC = VSORRES)

# ------------------------------------------------------------------------------
# Derive VSSTRESN (numeric result in standard units)
# ------------------------------------------------------------------------------
vs8 <- vs7 %>%
  mutate(VSSTRESN = suppressWarnings(as.numeric(VSORRES)))

# ------------------------------------------------------------------------------
# Derive VSSTRESU (standard units - same as original for this example)
# Apply unit conversions if needed
# ------------------------------------------------------------------------------
vs9 <- vs8 %>%
  mutate(VSSTRESU = VSORRESU)

# ------------------------------------------------------------------------------
# Derive VSSTAT (Completion Status) and VSREASND (Reason Not Done)
# If VSORRES is missing/blank, set VSSTAT = "NOT DONE"
# ------------------------------------------------------------------------------
vs10 <- vs9 %>%
  mutate(
    VSSTAT = if_else(is.na(VSORRES) | VSORRES == "", "NOT DONE", NA_character_),
    VSREASND = if_else(VSSTAT == "NOT DONE", "NOT PERFORMED", NA_character_)
  )

# ------------------------------------------------------------------------------
# Map VISITNUM and VISIT from source
# ------------------------------------------------------------------------------
vs11 <- vs10 %>%
  mutate(
    VISITNUM = as.numeric(VISITNUM),
    VISIT = as.character(VISIT)
  )

# ------------------------------------------------------------------------------
# Map VSDTC (Date/Time of Collection in ISO 8601 format)
# Assume VS_DATE is the source date variable
# ------------------------------------------------------------------------------
vs12 <- vs11 %>%
  mutate(
    VSDTC = as.character(VS_DATE)
  )

# ------------------------------------------------------------------------------
# Derive VSDY (Study Day of Collection)
# Join dm to get RFSTDTC (Reference Start Date)
# ------------------------------------------------------------------------------
dm_sub <- dm %>%
  select(USUBJID, RFSTDTC)

vs13 <- vs12 %>%
  left_join(dm_sub, by = "USUBJID") %>%
  mutate(
    VSDY = case_when(
      !is.na(VSDTC) & !is.na(RFSTDTC) ~ {
        vs_date <- as.Date(substr(VSDTC, 1, 10))
        rf_date <- as.Date(substr(RFSTDTC, 1, 10))
        diff <- as.numeric(vs_date - rf_date)
        if_else(vs_date >= rf_date, diff + 1, diff)
      },
      TRUE ~ NA_real_
    )
  ) %>%
  select(-RFSTDTC)

# ------------------------------------------------------------------------------
# Map VSPOS (Position during vital signs collection)
# ------------------------------------------------------------------------------
vs14 <- vs13 %>%
  mutate(VSPOS = if_else(!is.na(VSPOS), as.character(VSPOS), NA_character_))

# ------------------------------------------------------------------------------
# Derive VSSEQ (Sequence Number within subject)
# ------------------------------------------------------------------------------
vs15 <- vs14 %>%
  arrange(STUDYID, USUBJID, VSTESTCD, VISITNUM, VSDTC) %>%
  group_by(USUBJID) %>%
  mutate(VSSEQ = row_number()) %>%
  ungroup()

# ------------------------------------------------------------------------------
# Final sort and select variables per SDTM specification
# Variables in order per spec:
# STUDYID, VSSEQ, USUBJID, DOMAIN, VSTESTCD, VSTEST, VSCAT,
# VSORRES, VSORRESU, VSSTRESC, VSSTRESN, VSSTRESU, VSSTAT, VSREASND,
# VISITNUM, VISIT, VSDTC, VSDY, VSPOS
# ------------------------------------------------------------------------------

vs <- vs15 %>%
  arrange(STUDYID, USUBJID, VSTESTCD, VISITNUM, VSSEQ) %>%
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
  )

# -- END VS -- #

# -- BEGIN SUPPVS -- #

# Define qualifier metadata
qual_meta <- tribble(
  ~qnam,      ~qlabel,
  "VSCLSIG",  "Clinically Significant?: Yes No",
  "VSFAST",   "Fasting?: Yes No",
  "VSLOC",    "Location of Measurement"
)

# Merge VS domain with raw data to get qualifier variables.
# VSCLSIG/VSFAST/VSLOC are visit-level attributes (one value per subject per
# visit in raw_vs), while `vs` has one row per subject per visit per test —
# joining on STUDYID+USUBJID alone (no VISITNUM) would cross-multiply every
# test row against every visit's raw_vs row instead of matching same-visit
# records only. Also take one representative vs record per visit (slice(1))
# so the visit-level qualifier isn't duplicated across each of that visit's
# VSTESTCD rows.
vs_with_qual <- vs %>%
  select(STUDYID, USUBJID, VISITNUM, VSSEQ) %>%
  group_by(STUDYID, USUBJID, VISITNUM) %>%
  slice(1) %>%
  ungroup() %>%
  inner_join(
    raw_vs %>%
      select(STUDYID, USUBJID, VISITNUM, VSCLSIG, VSFAST, VSLOC),
    by = c("STUDYID", "USUBJID", "VISITNUM")
  )

# Pivot qualifier variables to long format
suppvs <- vs_with_qual %>%
  pivot_longer(
    cols = c(VSCLSIG, VSFAST, VSLOC),
    names_to = "QNAM",
    values_to = "QVAL"
  ) %>%
  filter(!is.na(QVAL) & QVAL != "") %>%
  left_join(qual_meta, by = c("QNAM" = "qnam")) %>%
  mutate(
    RDOMAIN = "VS",
    IDVAR = "VSSEQ",
    IDVARVAL = as.character(VSSEQ),
    QVAL = as.character(QVAL),
    QORIG = "CRF",
    QEVAL = NA_character_
  ) %>%
  select(
    STUDYID,
    RDOMAIN,
    USUBJID,
    IDVAR,
    IDVARVAL,
    QNAM,
    QLABEL = qlabel,
    QVAL,
    QORIG,
    QEVAL
  ) %>%
  arrange(STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM)

# -- END SUPPVS -- #

# -- Verification -- #
# glimpse(vs)
# table(vs$DOMAIN)

# End of vs.R
