#!/usr/bin/env bash
set -euo pipefail

export DESIGNS="$(pwd)/designs"
ENVFILE=".env"

if [ -f "${ENVFILE}" ]; then
	source "${ENVFILE}"
fi

if [ -z ${CONTAINER_NAME+z} ]; then
	CONTAINER_NAME="iic-osic-tools_chipathon_xvnc_uid_"$(id -u)
fi

function docker_exec() {
    docker exec -it  --user root ${CONTAINER_NAME} "$@"
}

# Script developed assited by Gemini AI

# --- CONFIGURATION ---
GDRIVE_REMOTE="gdrive_remote:SSCS_Tapeout_2026"
VERSION_TAG="v1"
WORKSPACE_DIR="./work"
OUTPUT_DIR="./dist"

PDK_LYP_PATH="${PDK_ROOT}/${PDK}/libs.tech/klayout/tech/gf180mcu.lyp"
FILL_DRC_SCRIPT="./scripts/run_fill.drc"
VERIFY_SCRIPT="./verify_fill.py"

mkdir -p "${WORKSPACE_DIR}" "${OUTPUT_DIR}"

echo "=================================================="
echo " 1. Downloading archives matching pattern from GDrive..."
echo "=================================================="
# Download files matching SSCS_2026_0[1-4]_v*.tar.xz
rclone copy "${GDRIVE_REMOTE}" "${WORKSPACE_DIR}" \
  --include "SSCS_2026_0[1-4]_v*.tar.xz" -v

cd "${WORKSPACE_DIR}"

# Find downloaded archives
ARCHIVES=$(ls SSCS_2026_0[1-4]_v*.tar.xz 2>/dev/null || true)

if [ -z "${ARCHIVES}" ]; then
  echo "[ERROR] No archives matched pattern SSCS_2026_0[1-4]_v*.tar.xz!"
  exit 1
fi

FILLED_PACK_DIR="SSCS_2026_filled_${VERSION_TAG}"
mkdir -p "${FILLED_PACK_DIR}"

# Track overall CI pass/fail status
FAILED_PROJECTS=()

for ARCHIVE in ${ARCHIVES}; do
  echo "--------------------------------------------------"
  echo " Processing Archive: ${ARCHIVE}"
  echo "--------------------------------------------------"

  # Extract folder name (e.g., SSCS_2026_01 from SSCS_2026_01_v1.tar.xz)
  FOLDER_NAME=$(echo "${ARCHIVE}" | sed -E 's/(SSCS_2026_0[1-4]).*/\1/')
  
  mkdir -p "${FOLDER_NAME}"
  tar -xJf "${ARCHIVE}" -C "${FOLDER_NAME}"

  # Locate top GDS inside extracted folder
  BASE_GDS=$(find "${FOLDER_NAME}" -name "*.gds" ! -name "*_filled.gds" | head -n 1)
  
  if [ -z "${BASE_GDS}" ]; then
    echo "[ERROR] No base GDS file found in ${FOLDER_NAME}!"
    FAILED_PROJECTS+=("${FOLDER_NAME} (Missing GDS)")
    continue
  fi

  FILLED_GDS="${FOLDER_NAME}/${FOLDER_NAME}_filled.gds"
  DIFF_GDS="${FOLDER_NAME}/${FOLDER_NAME}_diff_error.gds"

  echo " [STEP 3] Generating Dummy Fill for ${BASE_GDS}..."
  # Run PDK Fill script using KLayout batch mode
  klayout -b -r "${FILL_DRC_SCRIPT}" \
    -rd input="${BASE_GDS}" \
    -rd output="${FILLED_GDS}"

  echo " [STEP 4] Verifying Fill Integrity with verify_fill.py..."
  if klayout -b -r "../${VERIFY_SCRIPT}" \
    -rd input_a="${BASE_GDS}" \
    -rd input_b="${FILLED_GDS}" \
    -rd lyp="${PDK_LYP_PATH}" \
    -rd output="${DIFF_GDS}" \
    -rd tolerance=0.001; then
    
    echo "[PASS] ${FOLDER_NAME} passed verification!"
    # Move valid filled GDS to output staging directory
    cp "${FILLED_GDS}" "${FILLED_PACK_DIR}/${FOLDER_NAME}_filled.gds"
  else
    echo "[FAIL] ${FOLDER_NAME} failed verification! Functional layers damaged."
    FAILED_PROJECTS+=("${FOLDER_NAME}")
  fi
done

echo "=================================================="
echo " 5. Packaging & Uploading Results..."
echo "=================================================="

if [ ${#FAILED_PROJECTS[@]} -ne 0 ]; then
  echo "[FATAL] CI Pipeline failed for projects: ${FAILED_PROJECTS[*]}"
  exit 1
fi

# Compress all verified filled GDS files into a single release archive
OUTPUT_ARCHIVE="SSCS_2026_filled_${VERSION_TAG}.tar.xz"
tar -cJf "../${OUTPUT_DIR}/${OUTPUT_ARCHIVE}" -C . "${FILLED_PACK_DIR}"

# Upload result back to Google Drive
echo "Uploading ${OUTPUT_ARCHIVE} to Google Drive..."
rclone copy "../${OUTPUT_DIR}/${OUTPUT_ARCHIVE}" "${GDRIVE_REMOTE}" -v

echo "=================================================="
echo " SUCCESS: All projects verified and uploaded!"
echo "=================================================="
