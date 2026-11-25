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

cd "$BOTTLE_DIR/drive_c/Program Files (x86)/Steam"

echo "=== Launching Steam with -gamepadui ==="
env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" steam.exe -gamepadui -no-cef-sandbox > "$LOGS/steam_gamepad_test.log" 2>&1 &
STEAM_PID=$!

for i in {1..8}; do
    sleep 5
    echo "--- Tick $i (elapsed $((i*5))s) ---"
    /Volumes/Personal/WarpNest/inspect_windows || true
    
    if /Volumes/Personal/WarpNest/inspect_windows | grep -i -E "Steam|Sign in" | grep -v "Antigravity"; then
        echo "Found Steam window! Activating and capturing..."
        /Volumes/Personal/WarpNest/activate_wine || true
        sleep 2
        
        WIN_ID=$(/Volumes/Personal/WarpNest/inspect_windows | grep -i -E "Steam|Sign in" | grep -v "Antigravity" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')
        echo "Capturing Window ID: $WIN_ID"
        screencapture -l "$WIN_ID" -o "$SCRATCH/steam_gamepad_window.png" || true
        screencapture -x "$SCRATCH/steam_gamepad_screen.png" || true
        ls -lh "$SCRATCH/steam_gamepad_window.png" "$SCRATCH/steam_gamepad_screen.png"
        break
    fi
done

echo "=== Gamepad test finished ==="
