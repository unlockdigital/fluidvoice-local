#!/bin/bash
#
# Fetch the Parakeet TDT v2 CoreML model for OFFLINE preseeding (no HF token required).
#
# The model is public (FluidInference/parakeet-tdt-0.6b-v2-coreml, license CC-BY-4.0).
# This runs during DEV/PACKAGING setup (network allowed). It downloads the model, validates
# the required CoreML artifacts, writes a sha256 manifest, and records license/attribution
# into a gitignored vendor/ directory. package-release.sh then embeds this into the .app so
# first launch works with NO network and NO Hugging Face contact.
#
# Output:
#   vendor/models/parakeet-tdt-0.6b-v2-coreml/            (model files)
#   vendor/models/parakeet-tdt-0.6b-v2-coreml.manifest.json
#   vendor/models/parakeet-tdt-0.6b-v2-coreml.LICENSE.txt
#
# Usage:  ./scripts/fetch-parakeet-model.sh
#
set -euo pipefail

REPO_ID="FluidInference/parakeet-tdt-0.6b-v2-coreml"
MODEL_DIR_NAME="parakeet-tdt-0.6b-v2-coreml"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$REPO_DIR/vendor/models"
MODEL_DIR="$VENDOR/$MODEL_DIR_NAME"
MANIFEST="$VENDOR/$MODEL_DIR_NAME.manifest.json"
LICENSE_OUT="$VENDOR/$MODEL_DIR_NAME.LICENSE.txt"
REQUIRED=(Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecision.mlmodelc parakeet_vocab.json)

mkdir -p "$VENDOR"

echo "[1/4] Ensuring huggingface_hub is available..."
if ! python3 -c "import huggingface_hub" >/dev/null 2>&1; then
  echo "    installing huggingface_hub (user site)..."
  pip3 install --quiet --user "huggingface_hub>=0.23" || pip3 install --quiet "huggingface_hub>=0.23"
fi

echo "[2/4] Downloading $REPO_ID (anonymous, retry/backoff)..."
echo "    NOTE: Hugging Face rate-limits by IP (HTTP 429). If this fails, wait and re-run, or"
echo "          run from a different network during the setup window. No token is used."
ATTEMPTS="${FETCH_ATTEMPTS:-8}" \
HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_ENABLE_HF_TRANSFER=0 HF_HUB_DOWNLOAD_TIMEOUT=60 \
python3 - "$REPO_ID" "$MODEL_DIR" <<'PY'
import sys, os, time
from huggingface_hub import snapshot_download

repo_id, local_dir = sys.argv[1], sys.argv[2]
attempts = int(os.environ.get("ATTEMPTS", "8"))
delay = 8
last = None
for attempt in range(1, attempts + 1):
    try:
        snapshot_download(
            repo_id=repo_id,
            local_dir=local_dir,
            token=False,        # public model: never send/require a token
            max_workers=4,
        )
        print(f"    downloaded to {local_dir}")
        sys.exit(0)
    except Exception as e:  # incl. HfHubHTTPError (429/503) and LocalEntryNotFoundError wrapping them
        last = e
        if attempt < attempts:
            print(f"    attempt {attempt}/{attempts} failed ({type(e).__name__}); backing off {delay}s")
            time.sleep(delay); delay = min(delay * 2, 300); continue
print(f"ERROR: download failed after {attempts} attempts: {last}", file=sys.stderr)
sys.exit(2)
PY

echo "[3/4] Validating required artifacts..."
missing=0
for f in "${REQUIRED[@]}"; do
  if [ ! -e "$MODEL_DIR/$f" ]; then echo "    MISSING: $f"; missing=1; fi
done
[ "$missing" -eq 0 ] || { echo "ERROR: required artifacts missing — aborting"; exit 1; }
SIZE="$(du -sh "$MODEL_DIR" | awk '{print $1}')"
echo "    all required artifacts present ($SIZE)"

echo "[4/4] Writing sha256 manifest + license..."
python3 - "$MODEL_DIR" "$MANIFEST" "$REPO_ID" <<'PY'
import sys, os, json, hashlib
model_dir, manifest_path, repo_id = sys.argv[1], sys.argv[2], sys.argv[3]
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
files = {}
total = 0
for root, _, names in os.walk(model_dir):
    for n in names:
        p = os.path.join(root, n)
        rel = os.path.relpath(p, model_dir)
        if rel.endswith(".manifest.json"):
            continue
        files[rel] = sha256(p)
        total += os.path.getsize(p)
manifest = {
    "model": os.path.basename(model_dir),
    "version": "v2",
    "source": f"https://huggingface.co/{repo_id}",
    "license": "CC-BY-4.0",
    "total_bytes": total,
    "files": dict(sorted(files.items())),
}
with open(manifest_path, "w") as fh:
    json.dump(manifest, fh, indent=2)
print(f"    manifest: {len(files)} files, {total/1e6:.1f} MB -> {manifest_path}")
PY

cat > "$LICENSE_OUT" <<EOF
Parakeet TDT 0.6B v2 (CoreML)
Source: https://huggingface.co/$REPO_ID
License: CC-BY-4.0 (Creative Commons Attribution 4.0 International)

This model is redistributed with FluidVoice Hardened for offline, local-first speech
recognition. Attribution: NVIDIA Parakeet TDT, CoreML conversion by FluidInference.
See the model card for full terms: https://huggingface.co/$REPO_ID
EOF

echo "Done."
echo "  model:    $MODEL_DIR ($SIZE)"
echo "  manifest: $MANIFEST"
echo "  license:  $LICENSE_OUT"
echo "Next: ./scripts/package-release.sh  (embeds this into the .app)"
