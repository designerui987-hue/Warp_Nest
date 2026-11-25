#!/bin/bash
set -e

BOTTLE="/Volumes/Personal/WarpNest/bottles/SteamBottle"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"

echo "=== Terminating old wine ==="
"$WINESERVER" -k || true
pkill -9 -f "Steam|wine|cef" 2>/dev/null || true
sleep 1

echo "=== Ensuring steam.cfg ==="
cat << 'EOF' > "$STEAM_DIR/steam.cfg"
BootStrapperInhibitAll=Enable
BootStrapperForceSelfUpdate=Disable
EOF

echo "=== Launching Clean Stable Steam ==="
cd "$STEAM_DIR"
env WINEPREFIX="$BOTTLE" WINEDEBUG=-all "$WINE" steam.exe \
    -noverifyfiles \
    -nobootstrapupdate \
    -skipinitialbootstrap \
    -norepairfiles \
    -cef-disable-gpu \
    -no-cef-sandbox > "/Volumes/Personal/WarpNest/logs/clean_stable.log" 2>&1 &
PID=$!
echo "Spawned Steam PID $PID. Waiting 15s..."
sleep 15

/Volumes/Personal/WarpNest/ui_verifier || true
