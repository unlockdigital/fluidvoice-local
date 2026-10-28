#!/usr/bin/env python3
"""Check model setup's failure boundary with tiny synthetic files and no network."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('model_setup', Path(__file__).with_name('fetch-pinned-model.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)
with tempfile.TemporaryDirectory(prefix='fluidvoice-model-fixture-') as temporary:
    root = Path(temporary)
    model = root / 'model'
    model.mkdir()
    data = b'synthetic approved fixture'
    (model / 'weights.bin').write_bytes(data)
    manifest = {'files': {'weights.bin': hashlib.sha256(data).hexdigest()}}
    assert setup.verify(model, manifest) == 1
    for bad in [
        {'files': {}},
        {'files': {'../weights.bin': hashlib.sha256(data).hexdigest()}},
        {'files': {'weights.bin': '0' * 64}},
        {'files': {'missing.bin': hashlib.sha256(data).hexdigest()}},
    ]:
        try:
            setup.verify(model, bad)
        except (ValueError, FileNotFoundError):
            pass
        else:
            raise AssertionError('An invalid model fixture passed verification')
    (root / 'external.bin').write_bytes(data)
    (model / 'weights.bin').unlink()
    (model / 'weights.bin').symlink_to(root / 'external.bin')
    try:
        setup.verify(model, manifest)
    except ValueError:
        pass
    else:
        raise AssertionError('An external symlink passed verification')
print('PASS: pinned model integrity rejects corrupt, missing, unsafe and symlinked files')

with tempfile.TemporaryDirectory(prefix='fluidvoice-setup-fixture-') as temporary:
    import json
    root = Path(temporary)
    (root / 'models').mkdir()
    data = b'synthetic downloaded fixture'
    approved = {'model': 'fixture-model', 'source': 'https://example.invalid/model',
        'revision': '1' * 40, 'files': {'weights.bin': hashlib.sha256(data).hexdigest()}}
    manifest_path = root / 'models/approved.json'
    manifest_path.write_text(json.dumps(approved))
    (root / 'models/parakeet-tdt-0.6b-v2-coreml.LICENSE.txt').write_text('Synthetic attribution fixture')
    original_run, original_argv = subprocess.run, sys.argv
    calls = []
    def download(args, **kwargs):
        calls.append(args)
        assert '/resolve/' + '1' * 40 + '/weights.bin' in args[-1]
        Path(args[args.index('--output') + 1]).write_bytes(data)
    try:
        setup.REPO, setup.MANIFEST = root, manifest_path
        subprocess.run, sys.argv = download, ['fetch-pinned-model.py']
        setup.main()
        target = root / 'vendor/models/fixture-model/weights.bin'
        assert target.read_bytes() == data and len(calls) == 1
        setup.main()
        assert len(calls) == 1, 'Verified models must be reused without downloading'
        target.write_bytes(b'existing invalid model')
        try:
            setup.main()
        except ValueError:
            pass
        else:
            raise AssertionError('Invalid existing model was accepted')
        assert target.read_bytes() == b'existing invalid model' and len(calls) == 1
    finally:
        subprocess.run, sys.argv = original_run, original_argv
print('PASS: setup pins download URLs, reuses approved files and preserves invalid existing models')
