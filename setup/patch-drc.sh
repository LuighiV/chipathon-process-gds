#!/bin/bash

# This script patches the gf180 pdk to have the updated DRC rule deck

REPO_PV="https://github.com/fossi-foundation/globalfoundries-pdk-libs-gf180mcu_fd_pv.git"
COMMIT_PV="c036ebc596ad2199e2d3c7d828cd2ec5af7cb187"

DEST_DRC="/foss/pdks/gf180mcuD/libs.tech/klayout/tech/drc"

# Create temporary directory
TMP_DIR="$(mktemp -d)"
echo "Using temporary directory: ${TMP_DIR}"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

SRC_DRC="${TMP_DIR}/repo_pv/klayout/drc"

# Clone PV repository
git clone "${REPO_PV}" "${TMP_DIR}/repo_pv"
pushd "${TMP_DIR}/repo_pv"
git checkout ${COMMIT_PV}
popd

# Remove existing DRC directory
rm -rf "${DEST_DRC}"

# Copy new DRC directory
cp -r "${SRC_DRC}" "${DEST_DRC}"

# Remove testing directory inside destination
TESTING_DIR="${DEST_DRC}/testing"
rm -rf "${TESTING_DIR}"

# Allow write in drc folder (required for spice translation)
chmod 777 "${DEST_DRC}"

REPO_PR="https://github.com/fossi-foundation/globalfoundries-pdk-libs-gf180mcu_fd_pr.git"
COMMIT_PR="dea1a56647b25268c9fbaea748d823294f0b68f4"

DEST_PR="/foss/pdks/gf180mcuD/libs.tech/klayout/tech/macros"

SRC_PR="${TMP_DIR}/repo_pr/rules/klayout/macros"

# Clone PR repository
git clone "${REPO_PR}" "${TMP_DIR}/repo_pr"
pushd "${TMP_DIR}/repo_pr"
git checkout ${COMMIT_PR}
popd

rm -rf "${DEST_PR}"

cp -r "${SRC_PR}" "${DEST_PR}"
cp "${TMP_DIR}/repo_pr/tech/klayout/gf180mcu.lyp" "/foss/pdks/gf180mcuD/libs.tech/klayout/tech"
