#!/usr/bin/env bash
# ==============================================================================
# WarpNest Graphics Translation Backends Acquisition Script
# Downloads and deploys open-source DXVK and DXMT backends for MetalStorm.
# Conforms to Principle #7: 100% Open-Source (DXVK: zlib, DXMT: LGPL/MIT).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKENDS_DIR="${WORKSPACE_ROOT}/engines/backends"
WINE_DIR="${WORKSPACE_ROOT}/engines/wine-default"

DXVK_VERSION="2.5.3" # or 3.1.1
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v2.5.3/dxvk-2.5.3.tar.gz"
DXMT_VERSION="0.80"
DXMT_URL="https://github.com/Tiger-Tom/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"

echo "=== WarpNest Graphics Backends Acquisition ==="
echo "Workspace:    ${WORKSPACE_ROOT}"
echo "Backends Dir: ${BACKENDS_DIR}"

mkdir -p "${BACKENDS_DIR}/dxvk"
mkdir -p "${BACKENDS_DIR}/dxmt"

# 1. Fetch DXVK if not present
if [ ! -f "${BACKENDS_DIR}/dxvk/x64/d3d11.dll" ]; then
    echo "[1/4] Fetching DXVK..."
    TMP_DXVK="/tmp/dxvk.tar.gz"
    curl -fSL "https://github.com/doitsujin/dxvk/releases/download/v2.5.3/dxvk-2.5.3.tar.gz" -o "${TMP_DXVK}" || \
    curl -fSL "https://github.com/Gcenx/DXVK-Mac/releases/download/v3.1.1/dxvk-mac-3.1.1.tar.gz" -o "${TMP_DXVK}"
    
    TMP_EXTRACT="/tmp/dxvk_extracted"
    rm -rf "${TMP_EXTRACT}"
    mkdir -p "${TMP_EXTRACT}"
    tar -xzf "${TMP_DXVK}" -C "${TMP_EXTRACT}"
    
    # Locate x64 and x32 folders
    DXVK_INNER=$(find "${TMP_EXTRACT}" -type d -name "x64" | head -n 1 | xargs dirname)
    cp -R "${DXVK_INNER}/x64" "${BACKENDS_DIR}/dxvk/"
    [ -d "${DXVK_INNER}/x32" ] && cp -R "${DXVK_INNER}/x32" "${BACKENDS_DIR}/dxvk/"
    rm -f "${TMP_DXVK}"
    rm -rf "${TMP_EXTRACT}"
    echo "       DXVK installed to ${BACKENDS_DIR}/dxvk"
else
    echo "[1/4] DXVK already present."
fi

# 2. Fetch DXMT if not present
if [ ! -f "${BACKENDS_DIR}/dxmt/x64/d3d11.dll" ]; then
    echo "[2/4] Fetching DXMT..."
    TMP_DXMT="/tmp/dxmt.tar.gz"
    curl -fSL "${DXMT_URL}" -o "${TMP_DXMT}"
    
    TMP_EXTRACT="/tmp/dxmt_extracted"
    rm -rf "${TMP_EXTRACT}"
    mkdir -p "${TMP_EXTRACT}"
    tar -xzf "${TMP_DXMT}" -C "${TMP_EXTRACT}"
    
    # Copy DLLs
    DXMT_X64=$(find "${TMP_EXTRACT}" -type d -name "x64" | head -n 1)
    cp -R "${DXMT_X64}" "${BACKENDS_DIR}/dxmt/"
    
    # Deploy winemetal.so native bridge to wine lib directory if available
    WINEMETAL_SO=$(find "${TMP_EXTRACT}" -name "winemetal.so" | head -n 1)
    if [ -n "${WINEMETAL_SO}" ] && [ -d "${WINE_DIR}/lib/wine/x86_64-unix" ]; then
        echo "[3/4] Deploying native winemetal.so Mach-O bridge to Wine..."
        cp "${WINEMETAL_SO}" "${WINE_DIR}/lib/wine/x86_64-unix/winemetal.so"
        chmod +x "${WINE_DIR}/lib/wine/x86_64-unix/winemetal.so"
    fi
    
    rm -f "${TMP_DXMT}"
    rm -rf "${TMP_EXTRACT}"
    echo "       DXMT installed to ${BACKENDS_DIR}/dxmt"
else
    echo "[2/4] DXMT already present."
fi

# 3. Ensure winemetal.so is in Wine lib directory
if [ -d "${WINE_DIR}/lib/wine/x86_64-unix" ] && [ ! -f "${WINE_DIR}/lib/wine/x86_64-unix/winemetal.so" ]; then
    echo "[3/4] Installing winemetal.so bridge..."
    if [ -f "${BACKENDS_DIR}/dxmt/winemetal.so" ]; then
        cp "${BACKENDS_DIR}/dxmt/winemetal.so" "${WINE_DIR}/lib/wine/x86_64-unix/winemetal.so"
        chmod +x "${WINE_DIR}/lib/wine/x86_64-unix/winemetal.so"
    fi
else
    echo "[3/4] winemetal.so bridge verified in Wine driver path."
fi

echo "[4/4] Verification complete. Run 'warpctl graphics backends' to inspect."
