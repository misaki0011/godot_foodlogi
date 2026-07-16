#!/usr/bin/env bash
set -euo pipefail

GODOT_VERSION="4.6.2"
GODOT_RELEASE="${GODOT_VERSION}-stable"
INSTALL_DIR="${HOME}/.local/bin"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${INSTALL_DIR}"

if command -v godot >/dev/null 2>&1; then
  INSTALLED_VERSION="$(godot --version || true)"

  if [[ "${INSTALLED_VERSION}" == "${GODOT_VERSION}"* ]]; then
    echo "Godot ${INSTALLED_VERSION} is already installed."
    exit 0
  fi
fi

echo "Downloading Godot ${GODOT_RELEASE}..."

curl --fail --location \
  "https://downloads.godotengine.org/?flavor=stable&platform=linux.64&slug=linux.x86_64.zip&version=${GODOT_VERSION}" \
  --output "${TEMP_DIR}/godot.zip"

unzip -q "${TEMP_DIR}/godot.zip" -d "${TEMP_DIR}"

GODOT_BINARY="${TEMP_DIR}/Godot_v${GODOT_RELEASE}_linux.x86_64"

if [[ ! -f "${GODOT_BINARY}" ]]; then
  echo "Godot executable was not found after extraction." >&2
  exit 1
fi

install -m 0755 "${GODOT_BINARY}" "${INSTALL_DIR}/godot"

echo "Godot installed at ${INSTALL_DIR}/godot"
"${INSTALL_DIR}/godot" --version