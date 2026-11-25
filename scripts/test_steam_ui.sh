#!/bin/bash
set -e

BOTTLE_DIR="/Volumes/Personal/WarpNest/bottles/SteamBottle"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"
SCRATCH="/Volumes/Personal/WarpNest/scratch"
LOGS="/Volumes/Personal/WarpNest/logs"

mkdir -p "$SCRATCH" "$LOGS"

echo "=== Terminating existing Wine instances ==="
env WINEPREFIX="$BOTTLE_DIR" "$WINESERVER" -k || true
sleep 1

echo "=== Cleaning corrupted CEF caches ==="
rm -rf "$BOTTLE_DIR/drive_c/users/neerajgopi/AppData/Local/Steam/htmlcache"
rm -rf "$BOTTLE_DIR/drive_c/users/neerajgopi/AppData/Local/Steam/cefdata"

CONFIG="${1:-vdesktop}"
echo "=== Running Steam UI Test with config: $CONFIG ==="

cd "$BOTTLE_DIR/drive_c/Program Files (x86)/Steam"

if [ "$CONFIG" = "vdesktop" ]; then
    nohup env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" explorer /desktop=Steam,1280x800 "C:\\Program Files (x86)\\Steam\\steam.exe" -cef-disable-gpu -no-cef-sandbox > "$LOGS/steam_run.log" 2>&1 &
elif [ "$CONFIG" = "direct" ]; then
    nohup env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" steam.exe -cef-disable-gpu -no-cef-sandbox > "$LOGS/steam_run.log" 2>&1 &
elif [ "$CONFIG" = "direct_gpu" ]; then
    nohup env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" steam.exe -no-cef-sandbox > "$LOGS/steam_run.log" 2>&1 &
fi

STEAM_PID=$!
echo "Steam process detached (PID: $STEAM_PID). Waiting 25s for full initialization..."
sleep 25

echo "=== Inspecting Windows ==="
/Volumes/Personal/WarpNest/inspect_windows

echo "=== Activating Window ==="
/Volumes/Personal/WarpNest/activate_wine || true
sleep 2

echo "=== Capturing Screen ==="
screencapture -x "$SCRATCH/steam_screen.png"
ls -lh "$SCRATCH/steam_screen.png"

echo "=== Re-inspecting Windows after activation ==="
/Volumes/Personal/WarpNest/inspect_windows
