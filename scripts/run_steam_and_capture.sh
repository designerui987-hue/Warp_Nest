#!/bin/bash
set -e

BOTTLE_DIR="/Volumes/Personal/WarpNest/bottles/SteamBottle"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
SCRATCH="/Volumes/Personal/WarpNest/scratch"
LOGS="/Volumes/Personal/WarpNest/logs"

cd "$BOTTLE_DIR/drive_c/Program Files (x86)/Steam"

echo "=== Launching Steam with full network access ==="
env WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all "$WINE" steam.exe -cef-disable-gpu -no-cef-sandbox > "$LOGS/steam_live_ui.log" 2>&1 &
STEAM_PID=$!

echo "Monitoring Steam bootstrap and window creation (PID: $STEAM_PID)..."
for i in {1..12}; do
    sleep 5
    echo "--- Tick $i (elapsed: $((i*5))s) ---"
    /Volumes/Personal/WarpNest/inspect_windows || true
    tail -n 5 "$BOTTLE_DIR/drive_c/Program Files (x86)/Steam/logs/bootstrap_log.txt" 2>/dev/null || true
    
    # Check if login window appeared
    if /Volumes/Personal/WarpNest/inspect_windows | grep -q "Sign in to Steam"; then
        echo "Found 'Sign in to Steam' window! Activating and capturing..."
        /Volumes/Personal/WarpNest/activate_wine || true
        sleep 2
        
        # Extract window ID
        WIN_ID=$(/Volumes/Personal/WarpNest/inspect_windows | grep "Sign in to Steam" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')
        echo "Capturing Window ID: $WIN_ID"
        screencapture -l "$WIN_ID" -o "$SCRATCH/steam_login_window.png" || true
        screencapture -x "$SCRATCH/steam_full_screen.png" || true
        ls -lh "$SCRATCH/steam_login_window.png" "$SCRATCH/steam_full_screen.png"
        break
    fi
done

echo "=== Inspection complete ==="
