#!/bin/bash
set -euo pipefail
# Deprecated legacy script: session setup and diagnostics are now handled by
# `warpctl steam repair` and `warpctl steam launch` (SteamBridge).
# Native macOS Steam (~Library/Application Support/Steam) is never read or modified.
echo "Use 'warpctl steam diagnose' and 'warpctl steam launch' instead."
exit 0
