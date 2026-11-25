#!/bin/bash
set -e

BOTTLE="/Volumes/Personal/WarpNest/bottles/SteamBottle"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"

echo "=== Terminating old wine ==="
"$WINESERVER" -k || true
killall -9 wine-preloader wine64-preloader wineserver 2>/dev/null || true
sleep 1

echo "=== Running Phase 1: Verified Stable Steam Package Ingestion ==="
cd "$STEAM_DIR"
env WINEPREFIX="$BOTTLE" WINEDEBUG=-all "$WINE" steam.exe \
    -forcesteamupdate \
    -forcepackagedownload \
    -overridepackageurl "http://web.archive.org/web/20250306194830if_/media.steampowered.com/client" \
    -exitsteam > "/Volumes/Personal/WarpNest/logs/steam_downgrade.log" 2>&1 || true

echo "=== Phase 1 finished ==="
tail -n 25 "$STEAM_DIR/logs/bootstrap_log.txt" 2>/dev/null || true
