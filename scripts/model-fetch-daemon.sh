#!/bin/bash
#
# TCC-safe persistent model-fetch daemon (run by launchd).
#
# macOS TCC blocks launchd-spawned processes from reading/writing ~/Documents, so this daemon
# is self-contained and operates ENTIRELY under ~/Library/Application Support/FluidVoiceHardened:
# it downloads the Parakeet TDT v2 model (anonymous, no token) into a staging directory there,
# validates it, writes a sha256 manifest + license, drops a READY sentinel, and unloads itself.
#
# The in-session packaging step (scripts/package-release.sh) then copies the staged model into
# the repo's vendor/ and embeds it into the .app. This script is COPIED into the daemon home by
# install-model-fetch-daemon.sh and run from there (never from ~/Documents).
#
set -uo pipefail

REPO_ID="FluidInference/parakeet-tdt-0.6b-v2-coreml"
MODEL_NAME="parakeet-tdt-0.6b-v2-coreml"
HOME_DIR="$HOME/Library/Application Support/FluidVoiceHardened"
STAGING="$HOME_DIR/model-staging"
MODEL_DIR="$STAGING/$MODEL_NAME"
MANIFEST="$STAGING/$MODEL_NAME.manifest.json"
LICENSE_OUT="$STAGING/$MODEL_NAME.LICENSE.txt"
READY="$STAGING/READY"
STATUS="$HOME_DIR/STATUS.txt"
LABEL="com.unlockdigital.fluidvoicehardened.modelfetch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REQ=(Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecision.mlmodelc parakeet_vocab.json)

mkdir -p "$STAGING"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$STATUS"; }
unload_self() { launchctl unload "$PLIST" 2>/dev/null || launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; }

model_valid() {
  [ -d "$MODEL_DIR" ] || return 1
  [ -f "$MANIFEST" ] || return 1
  for f in "${REQ[@]}"; do [ -e "$MODEL_DIR/$f" ] || return 1; done
  local mb; mb="$(du -sm "$MODEL_DIR" 2>/dev/null | awk '{print $1}')"
  [ "${mb:-0}" -ge 50 ]
}

# Done already? stop.
if [ -f "$READY" ] && model_valid; then unload_self; exit 0; fi

log "daemon run start (staging fetch)"
if [ -d "$MODEL_DIR" ] && ! model_valid; then rm -rf "$MODEL_DIR" "$MANIFEST" "$READY"; fi

if ! command -v python3 >/dev/null 2>&1; then log "python3 not on PATH; cannot fetch"; exit 0; fi
python3 -c "import huggingface_hub" >/dev/null 2>&1 || pip3 install --quiet --user "huggingface_hub>=0.23" >> "$STATUS" 2>&1 || true

HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_DOWNLOAD_TIMEOUT=60 \
python3 - "$REPO_ID" "$MODEL_DIR" >> "$STATUS" 2>&1 <<'PY'
import sys, time
from huggingface_hub import snapshot_download
repo_id, local_dir = sys.argv[1], sys.argv[2]
delay = 8
for attempt in range(1, 5):
    try:
        snapshot_download(repo_id=repo_id, local_dir=local_dir, token=False, max_workers=4)
        print("    snapshot ok"); sys.exit(0)
    except Exception as e:
        print(f"    attempt {attempt}/4 failed: {type(e).__name__}")
        if attempt < 4:
            time.sleep(delay); delay = min(delay * 2, 120)
sys.exit(2)
PY

if ! model_valid; then log "model not ready yet (HF likely rate-limited); staying scheduled"; exit 0; fi

# Write manifest + license, then mark READY.
python3 - "$MODEL_DIR" "$MANIFEST" "$REPO_ID" >> "$STATUS" 2>&1 <<'PY'
import sys, os, json, hashlib
model_dir, manifest_path, repo_id = sys.argv[1], sys.argv[2], sys.argv[3]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for c in iter(lambda: fh.read(1024*1024), b""): h.update(c)
    return h.hexdigest()
files, total = {}, 0
for root, _, names in os.walk(model_dir):
    for n in names:
        p = os.path.join(root, n); rel = os.path.relpath(p, model_dir)
        if rel.endswith(".manifest.json"): continue
        files[rel] = sha(p); total += os.path.getsize(p)
json.dump({"model": os.path.basename(model_dir), "version": "v2",
           "source": f"https://huggingface.co/{repo_id}", "license": "CC-BY-4.0",
           "total_bytes": total, "files": dict(sorted(files.items()))},
          open(manifest_path, "w"), indent=2)
print(f"    manifest: {len(files)} files, {total/1e6:.1f} MB")
PY

cat > "$LICENSE_OUT" <<EOF
Parakeet TDT 0.6B v2 (CoreML) — https://huggingface.co/$REPO_ID — License: CC-BY-4.0
Redistributed with FluidVoice Hardened for offline local-first ASR.
EOF

touch "$READY"
log "STAGING_READY ($(du -sh "$MODEL_DIR" | awk '{print $1}')); model staged at $MODEL_DIR"
log "run ./scripts/package-release.sh in the repo to embed + verify the offline build"
unload_self
