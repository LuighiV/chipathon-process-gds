#!/bin/bash

BASE_PATH="/foss/designs/libs/to_tapeout/tapeout_v5"
SCRIPT_PATH="/foss/designs/scripts/process_gds/verify_fill.py"

GDS_NAME="SSCS_2026_01"
FOLDER_GDS=${BASE_PATH}"/"${GDS_NAME}

INPUT_GDS=${FOLDER_GDS}"/"${GDS_NAME}.gds
INPUT_GDS_FILLED=${FOLDER_GDS}"/"${GDS_NAME}_filled.gds

DIFF_GDS=${FOLDER_GDS}"/"${GDS_NAME}_diff.gds

\klayout -b -r verify_fill.py \
  -rd input_a=${INPUT_GDS} \
  -rd input_b=${INPUT_GDS_FILLED} \
  -rd lyp=$PDK_ROOT/$PDK/libs.tech/klayout/tech/gf180mcu.lyp \
  -rd output=${DIFF_GDS} \
  -rd tolerance=0.001
