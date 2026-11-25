#!/bin/bash
set -e

BOTTLE="/Volumes/Personal/WarpNest/bottles/SteamBottle"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"
SCRATCH="/Volumes/Personal/WarpNest/scratch"
LOGS="/Volumes/Personal/WarpNest/logs"

echo "=== Terminating all existing Wine and Steam processes ==="
pkill -9 -f "Steam|wine|cef|wineserver" 2>/dev/null || true
sleep 1
"$WINESERVER" -k || true
sleep 1

echo "=== Configuring environment ==="
export WINEPREFIX="$BOTTLE"
export VK_ICD_FILENAMES="/Volumes/Personal/WarpNest/engines/wine-default/share/vulkan/icd.d/MoltenVK_icd.json"
export DYLD_FALLBACK_LIBRARY_PATH="/Volumes/Personal/WarpNest/engines/wine-default/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,d3d9=n,b"

echo "=== Purging CEF cache ==="
rm -rf "$BOTTLE/drive_c/users/neerajgopi/AppData/Local/Steam/htmlcache"
rm -rf "$BOTTLE/drive_c/users/neerajgopi/AppData/Local/Steam/cefdata"

echo "=== Launching Steam Client with DXVK / MoltenVK ==="
cd "$STEAM_DIR"
WINEDEBUG=-all "$WINE" steam.exe \
    -noverifyfiles \
    -nobootstrapupdate \
    -skipinitialbootstrap \
    -norepairfiles \
    -overridepackageurl \
    -no-cef-sandbox > "$LOGS/steam_run_dxvk.log" 2>&1 &
STEAM_PID=$!
echo "Steam PID: $STEAM_PID"

echo "=== Starting verification loop ==="
MAX_ATTEMPTS=10
SUCCESS=0

for i in $(seq 1 $MAX_ATTEMPTS); do
    sleep 5
    echo "--- Poll $i / $MAX_ATTEMPTS (elapsed $((i*5))s) ---"
    
    # Activate Wine windows
    /Volumes/Personal/WarpNest/activate_wine 2>/dev/null || true
    
    # Run UI verifier
    /Volumes/Personal/WarpNest/ui_verifier > "$SCRATCH/verifier_poll_$i.log" 2>&1 || true
    cat "$SCRATCH/verifier_poll_$i.log"
    
    if grep -q "SUCCESS: Visible rendered Steam UI confirmed" "$SCRATCH/verifier_poll_$i.log"; then
        echo ">>> SUCCESS DETECTED AT ATTEMPT $i! <<<"
        SUCCESS=1
        break
    fi
done

# Full screen capture
/usr/sbin/screencapture -x "$SCRATCH/final_screen.png" || true
echo "Verification finished with SUCCESS=$SUCCESS"
