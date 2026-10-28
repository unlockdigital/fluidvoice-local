#!/bin/bash
#
# Install a TCC-safe launchd LaunchAgent that persistently retries the model download (surviving
# the Claude session / restarts). The daemon runs entirely under ~/Library (NOT ~/Documents, which
# macOS TCC blocks for launchd) and stages the model there. It self-unloads once the model is
# fully downloaded + validated. Then run ./scripts/package-release.sh (in the repo) to embed it.
#
# Usage:
#   ./scripts/install-model-fetch-daemon.sh           # deploy + load (runs now, then every 30 min)
#   ./scripts/install-model-fetch-daemon.sh --remove  # unload + delete the LaunchAgent + staging
#
set -euo pipefail

REPO="~/Documents/CODEX/FLUIDVOICE"
LABEL="com.unlockdigital.fluidvoicehardened.modelfetch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HOME_DIR="$HOME/Library/Application Support/FluidVoiceHardened"
DAEMON_SRC="$REPO/scripts/model-fetch-daemon.sh"
DAEMON_DST="$HOME_DIR/model-fetch-daemon.sh"
INTERVAL="${INTERVAL:-1800}"   # 30 minutes

if [ "${1:-}" = "--remove" ]; then
  launchctl unload "$PLIST" 2>/dev/null || launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$HOME_DIR/model-staging"
  echo "Removed LaunchAgent $LABEL and staging."
  exit 0
fi

mkdir -p "$HOME_DIR" "$HOME/Library/LaunchAgents"
# Copy the daemon OUT of ~/Documents so launchd can execute it without Full Disk Access.
cp "$DAEMON_SRC" "$DAEMON_DST"
chmod +x "$DAEMON_DST"

# launchd has a minimal PATH; include the dir of the current python3 so huggingface_hub is found.
PY3DIR="$(cd "$(dirname "$(command -v python3)")" && pwd)"
DAEMON_PATH="$PY3DIR:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DAEMON_DST</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>$DAEMON_PATH</string></dict>
    <key>StartInterval</key><integer>$INTERVAL</integer>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$HOME_DIR/daemon.out.log</string>
    <key>StandardErrorPath</key><string>$HOME_DIR/daemon.err.log</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Installed TCC-safe LaunchAgent: $LABEL (runs now, then every ${INTERVAL}s)"
echo "Daemon home:  $HOME_DIR"
echo "Status log:   $HOME_DIR/STATUS.txt"
echo "Staged model: $HOME_DIR/model-staging/$ ... (READY sentinel when complete)"
echo "When READY, run:  cd $REPO && ./scripts/package-release.sh   (embeds + verifies offline build)"
echo "Remove with:      ./scripts/install-model-fetch-daemon.sh --remove"
