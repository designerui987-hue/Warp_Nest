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

echo "=== Configuring Offline Mode in loginusers.vdf ==="
cat << 'EOF' > "$STEAM_DIR/config/loginusers.vdf"
"users"
{
	"76561199149275705"
	{
		"AccountName"		"neerajgopi"
		"PersonaName"		"JOYBOY"
		"RememberPassword"		"1"
		"WantsOfflineMode"		"1"
		"SkipOfflineModeWarning"		"1"
		"AutoLogin"		"1"
		"timestamp"		"1794036833"
	}
}
EOF

echo "=== Configuring Registry for Offline Mode ==="
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v AutoLoginUser /t REG_SZ /d "neerajgopi" /f
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v RememberPassword /t REG_DWORD /d 1 /f
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v AlreadyRetriedOfflineMode /t REG_DWORD /d 1 /f
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v WantsOfflineMode /t REG_DWORD /d 1 /f
env WINEPREFIX="$BOTTLE" "$WINE" reg add "HKCU\\Software\\Valve\\Steam" /v StartupMode /t REG_DWORD /d 0 /f

echo "=== Launching Steam in Offline Mini Mode ==="
cd "$STEAM_DIR"
env WINEPREFIX="$BOTTLE" WINEDEBUG=-all "$WINE" steam.exe -no-browser "+open" "steam://open/minigameslist" > "/Volumes/Personal/WarpNest/logs/steam_offline_mini.log" 2>&1 &
PID=$!
echo "Spawned Steam PID $PID. Waiting 15s..."
sleep 15

/Volumes/Personal/WarpNest/ui_verifier || true
