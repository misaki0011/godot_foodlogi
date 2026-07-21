#!/usr/bin/env bash
set -euo pipefail

GODOT_VERSION="4.6.2"
GODOT_RELEASE="${GODOT_VERSION}-stable"
INSTALL_DIR="${HOME}/.local/bin"
TEMPLATES_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_RELEASE}"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${INSTALL_DIR}"

if [[ -x "${INSTALL_DIR}/godot" ]] && "${INSTALL_DIR}/godot" --version 2>/dev/null | grep -q "^${GODOT_VERSION}"; then
  echo "Godot ${GODOT_VERSION} is already installed at ${INSTALL_DIR}/godot."
else
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
fi

"${INSTALL_DIR}/godot" --version

if [[ -f "${TEMPLATES_DIR}/version.txt" ]]; then
  echo "Godot ${GODOT_RELEASE} export templates are already installed at ${TEMPLATES_DIR}."
else
  echo "Downloading Godot ${GODOT_RELEASE} export templates..."

  curl --fail --location --max-time 600 \
    "https://downloads.godotengine.org/?flavor=stable&version=${GODOT_VERSION}&platform=linux.64&slug=export_templates.tpz" \
    --output "${TEMP_DIR}/export_templates.tpz"

  rm -rf "${TEMP_DIR}/templates"
  unzip -q "${TEMP_DIR}/export_templates.tpz" -d "${TEMP_DIR}"

  if [[ ! -d "${TEMP_DIR}/templates" ]]; then
    echo "Export templates directory was not found after extraction." >&2
    exit 1
  fi

  mkdir -p "${TEMPLATES_DIR}"
  cp -a "${TEMP_DIR}/templates/." "${TEMPLATES_DIR}/"

  echo "Export templates installed at ${TEMPLATES_DIR}"
fi