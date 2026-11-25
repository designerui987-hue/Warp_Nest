#!/bin/bash
set -e

BOTTLE_DIR="/Volumes/Personal/WarpNest/bottles/SteamBottle"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"
SCRATCH="/Volumes/Personal/WarpNest/scratch"
LOGS="/Volumes/Personal/WarpNest/logs"

echo "=== Terminating existing Wine instances ==="
env WINEPREFIX="$BOTTLE_DIR" "$WINESERVER" -k || true
sleep 1

echo "=== Cleaning caches ==="
rm -rf "$BOTTLE_DIR/drive_c/users/neerajgopi/AppData/Local/Steam/htmlcache"
rm -rf "$BOTTLE_DIR/drive_c/users/neerajgopi/AppData/Local/Steam/cefdata"

cd "$BOTTLE_DIR/drive_c/Program Files (x86)/Steam"

echo "=== Launching Steam with resolved steamloopback.host ==="
env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" steam.exe -no-cef-sandbox > "$LOGS/steam_loopback_test.log" 2>&1 &
STEAM_PID=$!

for i in {1..12}; do
    sleep 5
    echo "--- Tick $i (elapsed $((i*5))s) ---"
    /Volumes/Personal/WarpNest/inspect_windows || true
    
    if /Volumes/Personal/WarpNest/inspect_windows | grep -q "Sign in to Steam"; then
        echo "Found 'Sign in to Steam' window! Waiting 5s for DOM render..."
        sleep 5
        /Volumes/Personal/WarpNest/activate_wine || true
        sleep 2
        
        WIN_ID=$(/Volumes/Personal/WarpNest/inspect_windows | grep "Sign in to Steam" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')
        echo "Capturing Window ID: $WIN_ID"
        screencapture -l "$WIN_ID" -o "$SCRATCH/steam_login_resolved.png" || true
        screencapture -x "$SCRATCH/steam_screen_resolved.png" || true
        ls -lh "$SCRATCH/steam_login_resolved.png" "$SCRATCH/steam_screen_resolved.png"
        break
    fi
done

echo "=== Test script finished ==="
