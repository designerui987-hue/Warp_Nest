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

# Reset DllOverrides to builtin for steam client stability
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Wine\\DllOverrides" /v d3d11 /t REG_SZ /d "builtin" /f
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Wine\\DllOverrides" /v dxgi /t REG_SZ /d "builtin" /f

# Clear corrupted CEF caches
rm -rf "$BOTTLE/drive_c/users/neerajgopi/AppData/Local/Steam/htmlcache"
rm -rf "$BOTTLE/drive_c/users/neerajgopi/AppData/Local/Steam/cefdata"

cd "$STEAM_DIR"

echo "=== Launching Steam with DNS64 Loopback Override ==="
env WINEPREFIX="$BOTTLE" WINEDLLOVERRIDES="dxgi,d3d9,d3d10core,d3d11=b" WINEDEBUG=-all "$WINE" steam.exe \
    -noverifyfiles \
    -nobootstrapupdate \
    -skipinitialbootstrap \
    -norepairfiles \
    -overridepackageurl \
    -no-cef-sandbox \
    -cef-disable-gpu \
    -cef-host-resolver-rules="MAP steamloopback.host 127.0.0.1" > "$LOGS/steam_dns_test.log" 2>&1 &
STEAM_PID=$!
echo "Steam PID $STEAM_PID launched. Polling window states..."

for i in {1..8}; do
    sleep 4
    echo "--- Poll $i (elapsed $((i*4))s) ---"
    /Volumes/Personal/WarpNest/activate_wine 2>/dev/null || true
    
    /Volumes/Personal/WarpNest/inspect_windows | grep -i -E "Sign in|Steam" || true
    
    /Volumes/Personal/WarpNest/ui_verifier > "$SCRATCH/ui_verifier_dns_$i.log" 2>&1 || true
    cat "$SCRATCH/ui_verifier_dns_$i.log"
    
    if grep -q "SUCCESS: Visible rendered Steam UI confirmed" "$SCRATCH/ui_verifier_dns_$i.log"; then
        echo ">>> SUCCESS DETECTED AT POLL $i! <<<"
        break
    fi
done

/usr/sbin/screencapture -x "$SCRATCH/steam_dns_screen.png" || true
echo "Test finished."
