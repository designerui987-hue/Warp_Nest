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

echo "=== Launching Steam inside 1280x800 Virtual Desktop on Windows 10 ==="
env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" explorer /desktop=Steam,1280x800 "C:\\Program Files (x86)\\Steam\\steam.exe" -no-cef-sandbox > "$LOGS/steam_vdesktop_win10.log" 2>&1 &
STEAM_PID=$!

for i in {1..8}; do
    sleep 5
    echo "--- Tick $i (elapsed $((i*5))s) ---"
    /Volumes/Personal/WarpNest/inspect_windows || true
    
    if /Volumes/Personal/WarpNest/inspect_windows | grep -i "Steam" | grep -v "Antigravity"; then
        echo "Found Steam Desktop window! Activating and capturing..."
        /Volumes/Personal/WarpNest/activate_wine || true
        sleep 2
        
        WIN_ID=$(/Volumes/Personal/WarpNest/inspect_windows | grep -i "Steam" | grep -v "Antigravity" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')
        echo "Capturing Window ID: $WIN_ID"
        screencapture -l "$WIN_ID" -o "$SCRATCH/steam_vdesktop_window.png" || true
        screencapture -x "$SCRATCH/steam_vdesktop_screen.png" || true
        ls -lh "$SCRATCH/steam_vdesktop_window.png" "$SCRATCH/steam_vdesktop_screen.png"
        break
    fi
done

echo "=== Virtual Desktop test finished ==="
