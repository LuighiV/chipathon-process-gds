#!/bin/bash
set -euo pipefail

PROJECT_PATH="${HOME}/chipathon2026/AutoMOS-chipathon2026"
ENVFILE="${PROJECT_PATH}/.env"
export DESIGNS="${PROJECT_PATH}/designs"

if [ -f "${ENVFILE}" ]; then
	source "${ENVFILE}"
fi

if [ -z ${CONTAINER_NAME+z} ]; then
	CONTAINER_NAME="iic-osic-tools_chipathon_xvnc_uid_"$(id -u)
fi

function sudo_docker_exec() {
    docker exec -i  --user root ${CONTAINER_NAME} "$@"
}

function docker_exec() {
    docker exec -i  ${CONTAINER_NAME} "$@"
}


PDK_ROOT=$( docker_exec /bin/bash -c 'source ~/.bashrc > /dev/null 2>&1;echo ${PDK_ROOT}' )
PDK=$( docker_exec /bin/bash -c 'source ~/.bashrc > /dev/null 2>&1;echo ${PDK}' )
echo "PDK:"$PDK
echo "PDK_ROOT:"$PDK_ROOT

VERSION_TAG="v7"



# Get the mount binding from container
# Read the bind string directly into two variables
IFS=':' read -r HOST_PATH CONTAINER_PATH _ < <(
  docker inspect --format '{{index .HostConfig.Binds 0}}' ${CONTAINER_NAME}
)

# Display the result
echo "Host Path:      $HOST_PATH"
echo "Container Path: $CONTAINER_PATH"
echo "Designs Path:   $DESIGNS"

if [[ ${HOST_PATH} != ${DESIGNS} ]]; then
   echo "Binding in container differs from .env configuration"
   exit 1
fi

RELATIVE_BASE_PATH="libs/to_tapeout/tapeout_"${VERSION_TAG}
BASE_PATH=${HOST_PATH}"/"${RELATIVE_BASE_PATH}
CONTAINER_BASE_PATH=${CONTAINER_PATH}"/"${RELATIVE_BASE_PATH}

echo "Container Base Path: $CONTAINER_BASE_PATH"

ARCHIVES=$( docker_exec /bin/bash -c 'ls '$CONTAINER_BASE_PATH'/SSCS_2026_0[1-4]_v*.tar.xz 2>/dev/null || true' )

echo $ARCHIVES
for ARCHIVE in ${ARCHIVES}; do

    GDS_NAME=$(echo "${ARCHIVE}" | sed -E 's/.*(SSCS_2026_0[1-4]).*/\1/')

    echo "GDS_NAME:"${GDS_NAME}
    FOLDER_GDS=${CONTAINER_BASE_PATH}"/"${GDS_NAME}

    INPUT_GDS=${FOLDER_GDS}"/"${GDS_NAME}.gds
    GDS_FILLED=${FOLDER_GDS}"/"${GDS_NAME}_filled.gds


    docker_exec  /bin/bash << EOF
source /headless/.bashrc > /dev/null 2>&1
klayout -b -zz -r ${PDK_ROOT}/${PDK}/libs.tech/klayout/tech/scripts/fill_all.rb -rd input=${INPUT_GDS} -rd output=${GDS_FILLED} -rd no_scribe_line=true
EOF

done


OUTPUT_ARCHIVE=${BASE_PATH}"/SSCS_2026_filled_${VERSION_TAG}.tar.xz"

tar -cvJf ${OUTPUT_ARCHIVE} -C ${BASE_PATH} $(find ${BASE_PATH} -name "*_filled.gds" -type f -printf "%P\n")
