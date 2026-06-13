#!/bin/sh
set -e

if [ "${PLATFORM_NAME}" != "iphoneos" ]; then
  exit 0
fi

if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] || [ "${CODE_SIGNING_REQUIRED:-YES}" = "NO" ]; then
  exit 0
fi

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  echo "warning: No code signing identity available; embedded frameworks were not re-signed."
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
if [ ! -d "${frameworks_dir}" ]; then
  exit 0
fi

find "${frameworks_dir}" -maxdepth 1 -type d -name "*.framework" -print0 | while IFS= read -r -d '' framework; do
  echo "Code Signing embedded framework ${framework}"
  /usr/bin/codesign \
    --force \
    --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
    ${OTHER_CODE_SIGN_FLAGS:-} \
    --preserve-metadata=identifier,entitlements \
    "${framework}"
done
