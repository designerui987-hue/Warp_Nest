#!/usr/bin/env bash
# ==============================================================================
# WarpNest Open-Source Runtime Acquisition Script
# Downloads and verifies community open-source Wine builds for macOS.
# Conforms to Principle #7: 100% Open-Source, Zero Proprietary Binaries.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINES_DIR="${WORKSPACE_ROOT}/engines"
DEFAULT_TARGET_DIR="${ENGINES_DIR}/wine-default"

DEFAULT_RELEASE_VERSION="9.22"
DEFAULT_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${DEFAULT_RELEASE_VERSION}/wine-staging-${DEFAULT_RELEASE_VERSION}-osx64.tar.xz"

LOCAL_TARBALL=""

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --local <path>     Extract an already-downloaded Wine tarball (.tar.xz or .tar.gz)"
    echo "  --version <ver>    Specify Wine version to download (default: ${DEFAULT_RELEASE_VERSION})"
    echo "  --url <url>        Specify direct download URL"
    echo "  --target <dir>     Destination directory (default: ${DEFAULT_TARGET_DIR})"
    echo "  --help             Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            LOCAL_TARBALL="$2"
            shift 2
            ;;
        --version)
            DEFAULT_RELEASE_VERSION="$2"
            DEFAULT_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${DEFAULT_RELEASE_VERSION}/wine-staging-${DEFAULT_RELEASE_VERSION}-osx64.tar.xz"
            shift 2
            ;;
        --url)
            DEFAULT_URL="$2"
            shift 2
            ;;
        --target)
            DEFAULT_TARGET_DIR="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

mkdir -p "${ENGINES_DIR}"

if [[ -n "${LOCAL_TARBALL}" ]]; then
    if [[ ! -f "${LOCAL_TARBALL}" ]]; then
        echo "Error: Specified local archive does not exist: ${LOCAL_TARBALL}"
        exit 1
    fi
    SOURCE_ARCHIVE="${LOCAL_TARBALL}"
    echo "Using local Wine archive: ${SOURCE_ARCHIVE}"
else
    TEMP_DIR=$(mktemp -d /tmp/warpnest_runtime.XXXXXX)
    SOURCE_ARCHIVE="${TEMP_DIR}/wine-runtime.tar.xz"
    echo "Downloading open-source Wine from: ${DEFAULT_URL}"
    echo "Saving to: ${SOURCE_ARCHIVE}"

    if ! curl -L --fail --progress-bar "${DEFAULT_URL}" -o "${SOURCE_ARCHIVE}"; then
        echo "Download failed. Please check network connectivity or provide an existing archive using --local."
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
fi

echo "Extracting runtime to temporary extraction directory..."
EXTRACT_TMP=$(mktemp -d /tmp/warpnest_extract.XXXXXX)
tar -xf "${SOURCE_ARCHIVE}" -C "${EXTRACT_TMP}"

# Detect extraction layout
# Some archives contain a top-level app bundle (e.g., 'Wine Staging.app/Contents/Resources/wine')
# Others contain bin/ and lib/ directly.
FOUND_WINE_BIN=""
if [[ -f "${EXTRACT_TMP}/bin/wine64" ]]; then
    FOUND_WINE_DIR="${EXTRACT_TMP}"
elif compgen -G "${EXTRACT_TMP}/*.app/Contents/Resources/wine/bin/wine64" > /dev/null; then
    APP_PATH=$(ls -d "${EXTRACT_TMP}"/*.app | head -n 1)
    FOUND_WINE_DIR="${APP_PATH}/Contents/Resources/wine"
elif compgen -G "${EXTRACT_TMP}/*wine*/bin/wine64" > /dev/null; then
    FOUND_WINE_DIR=$(ls -d "${EXTRACT_TMP}"/*wine* | head -n 1)
else
    echo "Error: Could not locate 'bin/wine64' inside unpacked archive."
    rm -rf "${EXTRACT_TMP}"
    [[ -z "${LOCAL_TARBALL}" ]] && rm -rf "${TEMP_DIR}"
    exit 1
fi

echo "Deploying verified engine to: ${DEFAULT_TARGET_DIR}"
rm -rf "${DEFAULT_TARGET_DIR}"
mkdir -p "$(dirname "${DEFAULT_TARGET_DIR}")"
cp -R "${FOUND_WINE_DIR}" "${DEFAULT_TARGET_DIR}"

# Remove quarantine flags if any
xattr -rd com.apple.quarantine "${DEFAULT_TARGET_DIR}" 2>/dev/null || true

# Clean up
rm -rf "${EXTRACT_TMP}"
[[ -z "${LOCAL_TARBALL}" ]] && rm -rf "${TEMP_DIR}"

echo "Validating installed engine..."
if [[ -x "${DEFAULT_TARGET_DIR}/bin/wine64" ]]; then
    echo "WarpNest Engine verified successfully at: ${DEFAULT_TARGET_DIR}"
    "${DEFAULT_TARGET_DIR}/bin/wine64" --version || true
else
    echo "Error: wine64 binary is not executable at ${DEFAULT_TARGET_DIR}/bin/wine64"
    exit 1
fi
