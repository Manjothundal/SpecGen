# ********************************************************************
# Program:    ta.R
# Domain:     TA (General)
# Purpose:    Create SDTM TA domain data frame
# Variables:  10
# Generated:  SpecGen Phase 5c - SDTM Program Generation (target = r)
#
# Output:     ta data frame (TA domain dataset)
#
# Variables:  STUDYID, DOMAIN, ARMCD, ARM, TAETORD, ETCD, ELEMENT, TABRANCH
#             ...
# ********************************************************************

# ============================================================================
# SDTM TA Domain: Trial Arms
# Events class - one row per planned arm element per arm
# ============================================================================

library(dplyr)

# -- BEGIN TA -- #

# ============================================================================
# Read source data
# ============================================================================
# raw_ta and dm are already in the R session

# ============================================================================
# Derive TA domain
# ============================================================================

ta <- raw_ta %>%
  # Ensure STUDYID is present
  mutate(STUDYID = if ("STUDYID" %in% names(.)) STUDYID else dm$STUDYID[1]) %>%
  
  # Assign DOMAIN
  mutate(DOMAIN = "TA") %>%
  
  # Map ARMCD: Planned Arm Code from protocol/source
  mutate(ARMCD = if ("ARMCD" %in% names(.)) ARMCD else NA_character_) %>%
  
  # Map ARM: Description of Planned Arm from protocol/source
  mutate(ARM = if ("ARM" %in% names(.)) ARM else NA_character_) %>%
  
  # Map TAETORD: Order of Element within Arm from protocol/source
  # Must be numeric per SDTM IG
  mutate(TAETORD = if ("TAETORD" %in% names(.)) as.numeric(TAETORD) else as.numeric(row_number())) %>%
  
  # Map ETCD: Element Code from protocol/source
  mutate(ETCD = if ("ETCD" %in% names(.)) ETCD else NA_character_) %>%
  
  # Map ELEMENT: Description of Element from protocol/source
  mutate(ELEMENT = if ("ELEMENT" %in% names(.)) ELEMENT else NA_character_) %>%
  
  # Map TABRANCH: Branch from protocol/source
  mutate(TABRANCH = if ("TABRANCH" %in% names(.)) TABRANCH else NA_character_) %>%
  
  # Map TATRANS: Transition Rule from protocol/source
  mutate(TATRANS = if ("TATRANS" %in% names(.)) TATRANS else NA_character_) %>%
  
  # Map EPOCH: Epoch from protocol/source
  mutate(EPOCH = if ("EPOCH" %in% names(.)) EPOCH else NA_character_) %>%
  
  # ============================================================================
  # Sort final dataset
  # ============================================================================
  arrange(STUDYID, ARMCD, TAETORD) %>%
  
  # ============================================================================
  # Select and order variables per SDTM specification
  # ============================================================================
  select(
    STUDYID,
    DOMAIN,
    ARMCD,
    ARM,
    TAETORD,
    ETCD,
    ELEMENT,
    TABRANCH,
    TATRANS,
    EPOCH
  )

# -- END TA -- #

# -- Verification -- #
# glimpse(ta)
# table(ta$DOMAIN)

# End of ta.R
