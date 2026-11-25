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

# Ensure steam.cfg exists to lock updates permanently
cat << 'EOF' > "$STEAM_DIR/steam.cfg"
BootStrapperInhibitAll=Enable
BootStrapperForceSelfUpdate=Disable
EOF

echo "=== Launching Stable Steam ==="
cd "$STEAM_DIR"
env WINEPREFIX="$BOTTLE" WINEDEBUG=-all "$WINE" steam.exe \
    -noverifyfiles \
    -nobootstrapupdate \
    -skipinitialbootstrap \
    -norepairfiles \
    -overridepackageurl \
    -cef-disable-gpu \
    -no-cef-sandbox > "/Volumes/Personal/WarpNest/logs/stable_steam.log" 2>&1 &
PID=$!
echo "Spawned Steam PID $PID. Waiting 15s..."
sleep 15

/Volumes/Personal/WarpNest/ui_verifier || true
