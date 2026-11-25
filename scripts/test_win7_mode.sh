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

echo "=== Cleaning web cache to clear rejected socket state ==="
rm -rf "$BOTTLE/drive_c/users/neerajgopi/AppData/Local/Steam/htmlcache"
rm -rf "$STEAM_DIR/appcache/httpcache"

echo "=== Repairing SteamService ==="
env WINEPREFIX="$BOTTLE" "$WINE" "C:\\Program Files (x86)\\Steam\\bin\\SteamService.exe" /repair || true

echo "=== Launching Steam with win7 fallback IPC ==="
cd "$STEAM_DIR"
env WINEPREFIX="$BOTTLE" WINEDEBUG=-all "$WINE" steam.exe -no-browser > "/Volumes/Personal/WarpNest/logs/steam_win7.log" 2>&1 &
PID=$!
echo "Spawned Steam PID $PID. Waiting 15s..."
sleep 15

/Volumes/Personal/WarpNest/ui_verifier || true
