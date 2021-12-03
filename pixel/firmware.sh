#!/bin/bash
#
# extract:
#
#   Setup pixel firmware
#
#
##############################################################################


### SET ###

# use bash strict mode
set -euo pipefail


### TRAPS ###

# trap signals for clean exit
trap 'exit $?' EXIT
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars/"
readonly top="${script_path}/../../../"

readonly extract_ota_py="${top}/tools/extract-utils/extract_ota.py"

readonly work_dir="${WORK_DIR:-/tmp/pixel}"

source "${vars_path}/devices"

readonly device="${1}"
source "${vars_path}/${device}"

readonly factory_dir="${work_dir}/${device}/${build_id}/factory/${device}-${build_id,,}"
readonly ota_zip="${work_dir}/${device}/${build_id}/$(basename ${ota_url})"
readonly ota_firmware_dir="${work_dir}/${device}/${build_id}/firmware"

readonly vendor_path="${top}/vendor/google/${device}"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

# Firmware included in our factory images,
# typically bootloader and radio
copy_factory_firmware() {
  cp "${factory_dir}"/bootloader-*.img "${vendor_path}/firmware/bootloader.img"
  cp "${factory_dir}"/radio-*.img "${vendor_path}/firmware/radio.img"
  if [[ "${device}" != "oriole" || "${device}" != "raven" ]]; then
    echo "TODO android-info.txt"
  else
    cp "${factory_dir}"/android-info.txt "${vendor_path}/android-info.txt"
  fi
}

# Unpack the seperate partitions needed for OTA
# from the factory image's bootloader.img
unpack_firmware() {
  # modem.img
  qc_image_unpacker -i "${factory_dir}"/radio-*.img -o "${ota_firmware_dir}"
  # All other ${firmware_partitions[@]}
  qc_image_unpacker -i "${factory_dir}"/bootloader-*.img -o "${ota_firmware_dir}"
}

extract_firmware() {
  echo "${ota_sha256} ${ota_zip}" | sha256sum --check --status
  python3 ${extract_ota_py} ${ota_zip} -o "${ota_firmware_dir}" -p ${firmware_partitions[@]}
}

# Firmware included in OTAs, separate partitions
# Can be extracted from bootloader.img inside the factory image,
# or directly from the OTA zip
copy_ota_firmware() {
  for fp in ${firmware_partitions[@]}; do
    cp "${ota_firmware_dir}/${fp}.img" "${vendor_path}/firmware/${fp}.img"
  done
}

setup_makefiles() {
  # I don't like this
  sed -i /endif/d "${vendor_path}/Android.mk"

  if [[ "${device}" != "oriole" || "${device}" != "raven" ]]; then
    echo "TODO TARGET_BOARD_INFO_FILE"
  else
    echo >> ${vendor_path}/BoardConfigVendor.mk
    echo "TARGET_BOARD_INFO_FILE := vendor/google/${device}/android-info.txt" >> ${vendor_path}/BoardConfigVendor.mk
  fi

  echo >> "${vendor_path}/Android.mk"
  echo "\$(call add-radio-file,firmware/bootloader.img,version-bootloader)" >> "${vendor_path}/Android.mk"
  echo "\$(call add-radio-file,firmware/radio.img,version-baseband)" >> "${vendor_path}/Android.mk"

  for fp in ${firmware_partitions[@]}; do
    echo "\$(call add-radio-file,firmware/${fp}.img)" >> "${vendor_path}/Android.mk"
  done
  echo >> "${vendor_path}/Android.mk"

  # I still don't like this
  echo endif >> "${vendor_path}/Android.mk"
}

# error message
# ARG1: error message for STDERR
# ARG2: error status
error_m() {
  echo "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

# print help message.
help_message() {
  echo "${help_message:-'No help available.'}"
}

main() {
  mkdir -p "${ota_firmware_dir}"
  mkdir -p "${vendor_path}/firmware"

  copy_factory_firmware
  # Not all devices need OTA, most are supported in image_unpacker
  if [[ -n ${needs_ota-} ]]; then
    extract_firmware
  else
    unpack_firmware
  fi
  copy_ota_firmware
  setup_makefiles
}

### RUN PROGRAM ###

main "${@}"


##