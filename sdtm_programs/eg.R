# ********************************************************************
# Program:    eg.R
# Domain:     EG (Findings)
# Purpose:    Create SDTM EG domain data frame
# Variables:  19
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     eg data frame (EG domain dataset)
#
# Variables:  STUDYID, EGSEQ, USUBJID, DOMAIN, EGTESTCD, EGTEST, EGCAT, EGORRES
#             ...
# ********************************************************************

# ==============================================================================
# SDTM EG Domain (ECG Data)
# Production R Script
# ==============================================================================

# Load required libraries
library(dplyr)
library(tidyr)

# -- BEGIN EG -- #

# ==============================================================================
# 1. RESHAPE AND PREPARE SOURCE DATA
# ==============================================================================

eg_long <- raw_eg %>%
  {if (!"USUBJID" %in% names(.)) {
    left_join(., 
              dm %>% select(STUDYID, USUBJID, any_of(c("SUBJID", "SITEID")), RFSTDTC),
              by = intersect(names(.), c("STUDYID", "SUBJID", "SITEID")))
  } else {
    left_join(., 
              dm %>% select(USUBJID, STUDYID, RFSTDTC),
              by = c("USUBJID", "STUDYID"))
  }} %>%
  pivot_longer(
    cols = matches("^(HR|QT|QTC|RR|PR|QRS|QTCB|QTCF)$", ignore.case = FALSE),
    names_to = "EGTESTCD",
    values_to = "EGORRES_NUM",
    values_drop_na = FALSE
  )

# ==============================================================================
# 2. ASSIGN DOMAIN AND TEST METADATA
# ==============================================================================

eg <- eg_long %>%
  mutate(
    DOMAIN = "EG",
    
    EGTEST = case_when(
      EGTESTCD == "HR"    ~ "Heart Rate",
      EGTESTCD == "QT"    ~ "QT Duration",
      EGTESTCD == "QTC"   ~ "QT Corrected",
      EGTESTCD == "QTCB"  ~ "QT Corrected Bazett",
      EGTESTCD == "QTCF"  ~ "QT Corrected Fridericia",
      EGTESTCD == "RR"    ~ "RR Duration",
      EGTESTCD == "PR"    ~ "PR Duration",
      EGTESTCD == "QRS"   ~ "QRS Duration",
      TRUE ~ EGTESTCD
    ),
    
    EGCAT = "ECG",
    
    EGORRES = as.character(EGORRES_NUM),
    
    EGORRESU = case_when(
      EGTESTCD == "HR"    ~ "beats/min",
      EGTESTCD %in% c("QT", "QTC", "QTCB", "QTCF", "RR", "PR", "QRS") ~ "msec",
      TRUE ~ NA_character_
    )
  )

# ==============================================================================
# 3. DERIVE STANDARDIZED RESULTS (EGSTRESC, EGSTRESN, EGSTRESU)
# ==============================================================================

eg <- eg %>%
  mutate(
    EGSTRESC = EGORRES,
    
    EGSTRESN = case_when(
      !is.na(EGORRES_NUM) ~ as.numeric(EGORRES_NUM),
      !is.na(EGORRES) & EGORRES != "" ~ suppressWarnings(as.numeric(EGORRES)),
      TRUE ~ NA_real_
    ),
    
    EGSTRESU = EGORRESU
  )

# ==============================================================================
# 4. HANDLE COMPLETION STATUS AND REASON NOT DONE
# ==============================================================================

eg <- eg %>%
  mutate(
    EGSTAT = case_when(
      is.na(EGORRES) | EGORRES == "" ~ "NOT DONE",
      TRUE ~ NA_character_
    ),
    
    EGREASND = if ("EGREASND" %in% names(.)) {
      case_when(
        EGSTAT == "NOT DONE" ~ EGREASND,
        TRUE ~ NA_character_
      )
    } else {
      NA_character_
    }
  )

# ==============================================================================
# 5. MAP VISIT INFORMATION
# ==============================================================================

eg <- eg %>%
  mutate(
    VISITNUM = if ("VISITNUM" %in% names(.)) {
      as.numeric(VISITNUM)
    } else if ("VISIT" %in% names(.)) {
      as.numeric(gsub("\\D", "", VISIT))
    } else {
      NA_real_
    },
    
    VISIT = if ("VISIT" %in% names(.)) {
      as.character(VISIT)
    } else {
      NA_character_
    }
  )

# ==============================================================================
# 6. MAP TIMING VARIABLES
# ==============================================================================

eg <- eg %>%
  mutate(
    EGDTC = if ("EGDTC" %in% names(.)) {
      as.character(EGDTC)
    } else if ("EG_DATE" %in% names(.)) {
      as.character(EG_DATE)
    } else if ("EGDAT" %in% names(.)) {
      as.character(EGDAT)
    } else {
      NA_character_
    }
  ) %>%
  mutate(
    EGDY = case_when(
      !is.na(EGDTC) & !is.na(RFSTDTC) ~ {
        eg_date <- as.Date(substr(EGDTC, 1, 10))
        rfst_date <- as.Date(substr(RFSTDTC, 1, 10))
        diff <- as.numeric(eg_date - rfst_date)
        if_else(diff >= 0, diff + 1, diff)
      },
      TRUE ~ NA_real_
    )
  )

# ==============================================================================
# 7. MAP EVALUATOR/INTERPRETATION (if available in source)
# ==============================================================================

eg <- eg %>%
  mutate(
    EGEVAL = if ("EGEVAL" %in% names(.)) {
      as.character(EGEVAL)
    } else {
      NA_character_
    }
  )

# ==============================================================================
# 8. DERIVE SEQUENCE NUMBER
# ==============================================================================

eg <- eg %>%
  arrange(STUDYID, USUBJID, EGTESTCD, VISITNUM, EGDTC) %>%
  group_by(USUBJID) %>%
  mutate(EGSEQ = row_number()) %>%
  ungroup()

# ==============================================================================
# 9. FINAL SORT AND SELECT VARIABLES PER SPEC
# ==============================================================================

eg <- eg %>%
  arrange(STUDYID, USUBJID, EGSEQ) %>%
  select(
    STUDYID,
    EGSEQ,
    USUBJID,
    DOMAIN,
    EGTESTCD,
    EGTEST,
    EGCAT,
    EGORRES,
    EGORRESU,
    EGSTRESC,
    EGSTRESN,
    EGSTRESU,
    EGSTAT,
    EGREASND,
    VISITNUM,
    VISIT,
    EGDTC,
    EGDY,
    EGEVAL
  )

# -- END EG -- #

# ==============================================================================
# END OF SCRIPT
# ==============================================================================


# -- BEGIN SUPPEG -- #

# Create SUPPEG supplemental qualifier domain
suppeg <- eg %>%
  # Select key variables needed for SUPP domain
  select(STUDYID, USUBJID, EGSEQ) %>%
  left_join(
    raw_eg %>% select(STUDYID, USUBJID, EGCLSIG),
    by = c("STUDYID", "USUBJID")
  ) %>%
  # Create SUPPEG structure with qualifier variables
  mutate(
    RDOMAIN = "EG",
    IDVAR = "EGSEQ",
    IDVARVAL = as.character(EGSEQ)
  ) %>%
  # Pivot qualifier variables to long format
  pivot_longer(
    cols = c(EGCLSIG),
    names_to = "QNAM",
    values_to = "QVAL",
    values_transform = as.character
  ) %>%
  # Add QLABEL based on QNAM
  mutate(
    QLABEL = case_when(
      QNAM == "EGCLSIG" ~ "Clinically Significant",
      TRUE ~ NA_character_
    ),
    QORIG = "CRF",
    QEVAL = NA_character_
  ) %>%
  # Filter out missing QVAL
  filter(!is.na(QVAL) & QVAL != "") %>%
  # Select final variables in correct order
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
    EGCLSIG
  ) %>%
  # Sort as specified
  arrange(STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM)

# -- END SUPPEG -- #

# -- Verification -- #
# glimpse(eg)
# table(eg$DOMAIN)

# End of eg.R
