"""
Reference dictionary: metadata masking strings → BCL Convert OverrideCycles.

Each entry maps a masking string (as written in the metadata Excel file) to a
dict with:
    "override_cycles"  : expected OverrideCycles string in the SampleSheet
    "library_types"    : library types this combination is used for
    "notes"            : clarifying notes

Physical read lengths vary between instruments/runs, so a masking string can
produce different OverrideCycles depending on actual cycle counts.  The entries
below cover observed combinations from runs xR077–xR085, xR078, xR079, xR080,
xR081_B, xR082_A, xR083, mR490–mR492.

Notation:
    Y<n>      sequence (output to FASTQ)
    I<n>      index read (demultiplexing)
    N<n>      masked (not output)
    U<n>      UMI read (not index, not masked — legacy, avoid for BD ATAC)
    N<n> suffix appended when specified_len < physical_len (padding mask)
"""

# ---------------------------------------------------------------------------
# BD Rhapsody WTA
# ---------------------------------------------------------------------------
# R1 = cell barcode + UMI (51 bp), R2 = cDNA (71 bp); I2 is unused in WTA.
# The actual N-padding depends on physical cycle counts:
#   PE51_8_60_71  → Y51N1;I8;N60;Y71N1   (physical: 52 / 8 / 60 / 72)
#   PE151_10_10_151 → Y51N100;I8N2;N10;Y71N80  (physical: 151 / 10 / 10 / 151)

BD_WTA = {
    # xR085 (PE51_8_60_71)
    "R1:51, I1:8, I2:0, R2:71 [PE51_8_60_71]": {
        "override_cycles": "Y51N1;I8;N60;Y71N1",
        "library_types":   ["BD_WTA", "BD_SMK"],
        "notes": "N60 masks the 60-cycle I2 physical read entirely. "
                 "SMK (Sample Multiplexing Kit) libraries share the same OverrideCycles.",
    },
    # xR078, xR081 (PE151_10_10_151 physical, trimmed to 51/8/0/71)
    "R1:51, I1:8, I2:0, R2:71 [PE151_10_10_151]": {
        "override_cycles": "Y51N100;I8N2;N10;Y71N80",
        "library_types":   ["BD_WTA", "BD_SMK"],
        "notes": "Same logical masking as above but on a longer-cycle run. "
                 "N100/N80 pad out the unused cycles of R1/R2; N10 masks the 10-cycle I2.",
    },
}

# ---------------------------------------------------------------------------
# BD Rhapsody ATACseq
# ---------------------------------------------------------------------------
# R1 = genomic (50 bp), R2 = genomic (50 bp), I2 = Tn5 barcode (60 bp).
# BCL Convert must output I2 as an index FASTQ (I60 layout), NOT as a UMI.
# The old pipeline incorrectly stripped I2 from OverrideCycles + set TrimUMI,0,
# producing U60 (UMI layout) — this has been fixed as of xR085.

BD_ATAC = {
    "R1:50, I1:8, I2:60, R3:50": {
        "override_cycles": "Y50N2;I8;I60;Y50N22",
        "library_types":   ["BD_ATAC"],
        "notes": "I60 = barcode read output as I2 FASTQ (correct BD Rhapsody format). "
                 "N2/N22 pad to physical read lengths (52/72 cycles on NovaSeq X PE51_8_60_71 run). "
                 "Do NOT use U60 — that was a legacy bug (pipeline fix applied xR085).",
    },
    # Older metadata used 'U:60' prefix instead of 'I2:60' — maps to same result
    "R1:50, I1:8, U:60, R3:50": {
        "override_cycles": "Y50N2;I8;U60;Y50N22",
        "library_types":   ["BD_ATAC"],
        "notes": "Legacy metadata format using 'U:' prefix (older runs pre-xR085). "
                 "Produced U60 UMI layout — files required post-hoc renaming (R2→I2, R3→R2). "
                 "Prefer I2:60 masking going forward.",
    },
}

# ---------------------------------------------------------------------------
# 10x Genomics GEX (3' v3/v4 and 5' v2)
# ---------------------------------------------------------------------------
# R1 = cell barcode + UMI (26–28 bp), R2 = cDNA (90 bp); dual 10-bp index.

TEN_X_GEX = {
    # xR077, xR079 (PE151_10_10_151 physical)
    "R1:26, I1:10, I2:10, R2:90": {
        "override_cycles": "Y26N125;I10;I10N6;Y90N61",
        "library_types":   ["10x_GEX"],
        "notes": "3' v3 chemistry (26 bp R1). N125/N61 pad R1/R2; N6 pads I2 from 16→10.",
    },
    # xR078, xR081, xR083 (PE151_10_10_151)
    "R1:26, I1:10, I2:10, R2:90 [no I2 pad]": {
        "override_cycles": "Y26N125;I10;I10;Y90N61",
        "library_types":   ["10x_GEX"],
        "notes": "Same as above but on runs where physical I2 = 10 cycles exactly (no N padding).",
    },
    # 5' v2 (28 bp R1)
    "R1:28, I1:10, I2:10, R2:90": {
        "override_cycles": "Y28N123;I10;I10;Y90N61",
        "library_types":   ["10x_GEX"],
        "notes": "5' v2 / 3' v4 chemistry (28 bp R1). N123 pads R1.",
    },
}

# ---------------------------------------------------------------------------
# 10x Genomics Visium HD
# ---------------------------------------------------------------------------

TEN_X_VISIUM = {
    # xR079 (PE151_10_10_151)
    "R1:43, I1:10, I2:10, R2:75": {
        "override_cycles": "Y43N108;I10;I10N6;Y75N76",
        "library_types":   ["10x_Visium"],
        "notes": "VisiumHD: 43 bp spatial barcode read, 75 bp cDNA read. N6 pads I2.",
    },
    # xR083 (PE151_10_10_151, I2=10 physical)
    "R1:43, I1:10, I2:10, R2:53": {
        "override_cycles": "Y43N108;I10;I10;Y53N98",
        "library_types":   ["10x_Visium"],
        "notes": "VisiumHD HD variant with shorter R2 (53 bp). No I2 padding needed.",
    },
}

# ---------------------------------------------------------------------------
# 10x Genomics ATACseq
# ---------------------------------------------------------------------------
# 10x ATAC uses a special I2 read for the Tn5 barcode; historically this has
# been handled several ways depending on the pipeline version.

TEN_X_ATAC = {
    "R1:50, I1:8, Y2:0, R2:50": {
        "override_cycles": "Y50N101;I8N2;I16;Y50N101",
        "library_types":   ["10x_ATAC"],
        "notes": "Y2:0 signals the I2 position is a structural read — various override "
                 "patterns observed (I16, U16, Y16, I0N16) across pipeline versions. "
                 "I16 is the current preferred form (output I2 as 16-cycle index FASTQ).",
    },
}

# ---------------------------------------------------------------------------
# Standard bulk sequencing (RNA-seq, DNA-seq, ChIP-seq, ATAC-seq, etc.)
# ---------------------------------------------------------------------------
# Most standard libraries share the same masking and use dual 8-bp or 10-bp indexes.

STANDARD = {
    # Most common: 8 bp dual index, 10-cycle physical I1/I2 (pad 2)
    "R1:151, I1:8, I2:8, R2:151": {
        "override_cycles": "Y151;I8N2;I8N2;Y151",
        "library_types":   ["RNA-seq", "DNA-seq", "ChIP-seq", "ATAC-seq",
                             "Cut&Run", "EMseq", "AmpliSeq", "smMIP", "other"],
        "notes": "Standard dual-index library on PE151 10-10 runs. "
                 "N2 pads each index from 8 to the 10-cycle physical read.",
    },
    # 10 bp dual index, exact fit
    "R1:151, I1:10, I2:10, R2:151": {
        "override_cycles": "Y151;I10;I10;Y151",
        "library_types":   ["DNA-seq", "PIPseq"],
        "notes": "10 bp indexes with no padding needed.",
    },
    # 10 bp dual index, I2 has 16-cycle physical (N6 pad)
    "R1:151, I1:10, I2:10, R2:151 [I2-pad6]": {
        "override_cycles": "Y151;I10;I10N6;Y151",
        "library_types":   ["DNA-seq"],
        "notes": "As above but on runs where physical I2 = 16 cycles; N6 pads I2.",
    },
    # 6 bp I1, no I2 (e.g. older Nextera)
    "R1:151, I1:6, R2:151": {
        "override_cycles": "Y151;I6N4;N10;Y151",
        "library_types":   ["RNA-seq", "DNA-seq", "Ribo-seq", "other"],
        "notes": "Single 6-cycle index; N4 pads I1 to 10-cycle physical, N10 masks I2.",
    },
    # 8 bp I1, no I2 (e.g. some older kits)
    "R1:151, I1:8, R2:151 [no-I2]": {
        "override_cycles": "Y151;I8N2;N10;Y151",
        "library_types":   ["other"],
        "notes": "Single 8-cycle index on a 10-10 run; N2 pads I1, N10 masks I2.",
    },
}

# ---------------------------------------------------------------------------
# MiSeq / single-read runs
# ---------------------------------------------------------------------------

MISEQ = {
    "R1:251, I1:8, I2:8, R2:251": {
        "override_cycles": "Y251;I8;I8;Y251",
        "library_types":   ["DNA-seq", "RNA-seq"],
        "notes": "MiSeq v2 2×251 with exact 8-cycle indexes.",
    },
    "R1:251, I1:12": {
        "override_cycles": "Y251;I12",
        "library_types":   ["DNA-seq"],
        "notes": "MiSeq single-read with 12-cycle index.",
    },
    "R1:251, I1:6": {
        "override_cycles": "Y251;I6",
        "library_types":   ["other"],
        "notes": "MiSeq single-read with 6-cycle index.",
    },
}

# ---------------------------------------------------------------------------
# Combined flat lookup  (masking → override_cycles, ignoring physical-length variants)
# ---------------------------------------------------------------------------
# Useful for quick validation; key is the canonical masking string.

MASKING_TO_OC = {
    # BD
    "R1:51, I1:8, I2:0, R2:71":    "Y51N1;I8;N60;Y71N1",   # xR085 PE51_8_60_71
    "R1:50, I1:8, I2:60, R3:50":   "Y50N2;I8;I60;Y50N22",  # BD ATAC (I60 layout)
    # 10x
    "R1:26, I1:10, I2:10, R2:90":  "Y26N125;I10;I10N6;Y90N61",
    "R1:28, I1:10, I2:10, R2:90":  "Y28N123;I10;I10;Y90N61",
    "R1:43, I1:10, I2:10, R2:75":  "Y43N108;I10;I10N6;Y75N76",
    "R1:43, I1:10, I2:10, R2:53":  "Y43N108;I10;I10;Y53N98",
    "R1:50, I1:8, Y2:0, R2:50":    "Y50N101;I8N2;I16;Y50N101",
    # Standard
    "R1:151, I1:8, I2:8, R2:151":  "Y151;I8N2;I8N2;Y151",
    "R1:151, I1:10, I2:10, R2:151": "Y151;I10;I10;Y151",
    "R1:151, I1:6, R2:151":        "Y151;I6N4;N10;Y151",
    # MiSeq
    "R1:251, I1:8, I2:8, R2:251":  "Y251;I8;I8;Y251",
}
