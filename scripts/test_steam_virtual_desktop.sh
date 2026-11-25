#!/bin/bash
set -e

BOTTLE="/Volumes/Personal/WarpNest/bottles/SteamBottle"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"

echo "=== Terminating all existing wine/steam processes ==="
"$WINESERVER" -k || true
pkill -9 -f "Steam|wine|cef" 2>/dev/null || true
sleep 2

echo "=== Launching Steam inside Virtual Desktop ==="
cd "$STEAM_DIR"
env WINEPREFIX="$BOTTLE" WINEDEBUG=-all "$WINE" steam.exe \
    -noverifyfiles \
    -nobootstrapupdate \
    -skipinitialbootstrap \
    -norepairfiles \
    -cef-disable-gpu \
    -no-cef-sandbox > "/Volumes/Personal/WarpNest/logs/steam_vd_run.log" 2>&1 &
PID=$!
echo "Spawned Steam PID $PID. Waiting 20s for full window paint..."
sleep 20

/Volumes/Personal/WarpNest/ui_verifier || true
