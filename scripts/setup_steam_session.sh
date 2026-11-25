#!/bin/bash
set -e

BOTTLE_DIR="/Volumes/Personal/WarpNest/bottles/SteamBottle"
STEAM_WIN_DIR="$BOTTLE_DIR/drive_c/Program Files (x86)/Steam"
NATIVE_STEAM="$HOME/Library/Application Support/Steam"
WINE="/Volumes/Personal/WarpNest/engines/wine-default/bin/wine"
WINESERVER="/Volumes/Personal/WarpNest/engines/wine-default/bin/wineserver"

echo "=== Terminating any active Wine processes ==="
"$WINESERVER" -k || true
killall -9 wine-preloader wineserver 2>/dev/null || true
sleep 1

echo "=== Syncing native Steam session into SteamBottle ==="
mkdir -p "$STEAM_WIN_DIR/config"
mkdir -p "$STEAM_WIN_DIR/userdata"

# Copy login config
if [ -f "$NATIVE_STEAM/config/loginusers.vdf" ]; then
    cp -v "$NATIVE_STEAM/config/loginusers.vdf" "$STEAM_WIN_DIR/config/"
fi

# Copy userdata
if [ -d "$NATIVE_STEAM/userdata" ]; then
    cp -Rv "$NATIVE_STEAM/userdata/" "$STEAM_WIN_DIR/userdata/"
fi

# Copy config.vdf if present
if [ -f "$NATIVE_STEAM/config/config.vdf" ]; then
    # Merge/backup existing config
    cp "$STEAM_WIN_DIR/config/config.vdf" "$STEAM_WIN_DIR/config/config.vdf.bak" 2>/dev/null || true
    cp -v "$NATIVE_STEAM/config/config.vdf" "$STEAM_WIN_DIR/config/"
fi

# Copy DialogConfig.vdf
if [ -f "$NATIVE_STEAM/config/DialogConfig.vdf" ]; then
    cp -v "$NATIVE_STEAM/config/DialogConfig.vdf" "$STEAM_WIN_DIR/config/"
fi

echo "=== Updating Wine Registry with AutoLoginUser ==="
env WINEPREFIX="$BOTTLE_DIR" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v AutoLoginUser /t REG_SZ /d "neerajgopi" /f
env WINEPREFIX="$BOTTLE_DIR" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v RememberPassword /t REG_DWORD /d 1 /f
env WINEPREFIX="$BOTTLE_DIR" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v SuppressAutoRun /t REG_DWORD /d 0 /f

echo "=== Session setup completed successfully ==="
