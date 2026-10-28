#!/usr/bin/env python3
"""Explicit setup-time model fetch and read-only checksum verification.

The approved file list, SHA-256 values, and immutable revision live in models/.
No third-party Python packages or Hugging Face credentials are used.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / 'models/parakeet-tdt-0.6b-v2-coreml.manifest.json'

def checked_entries(manifest):
    if not manifest['files']:
        raise ValueError('The approved model manifest must contain files')
    for name, checksum in manifest['files'].items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or '\\' in name:
            raise ValueError('Unsafe approved model path')
        if len(checksum) != 64 or any(c not in '0123456789abcdef' for c in checksum):
            raise ValueError('Invalid approved SHA-256')
        yield name, checksum

def verify(directory, manifest):
    directory = Path(directory)
    if directory.is_symlink():
        raise ValueError('The model root must be a regular directory')
    directory = directory.resolve(strict=True)
    count = 0
    for name, expected in checked_entries(manifest):
        path = directory / name
        current = directory
        for part in PurePosixPath(name).parts:
            current = current / part
            if current.is_symlink():
                raise ValueError('Model paths must contain regular files and directories')
        if not path.is_file():
            raise ValueError('Approved model file is missing: ' + name)
        h = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(block)
        if h.hexdigest() != expected:
            raise ValueError('Model checksum mismatch: ' + name)
        count += 1
    return count

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-only', type=Path, help='Read and verify a model directory without fetching or writing')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if args.verify_only is not None:
        print('PASS: %d approved model files' % verify(args.verify_only, manifest))
        return
    revision = manifest['revision']
    if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise ValueError('An immutable model revision is required')
    curl = shutil.which('curl')
    if curl is None:
        raise RuntimeError('curl is required for explicit model setup')
    vendor = REPO / 'vendor/models'
    target = vendor / manifest['model']
    if target.exists():
        verify(target, manifest)  # An existing unapproved model is preserved and rejected.
    else:
        vendor.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.model-setup-', dir=vendor) as temporary:
            staged = Path(temporary) / manifest['model']
            staged.mkdir()
            for index, (name, _) in enumerate(checked_entries(manifest), start=1):
                destination = staged / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                url = manifest['source'] + '/resolve/' + revision + '/' + name
                print('Downloading approved file %d/%d: %s' % (index, len(manifest['files']), name), flush=True)
                subprocess.run([curl, '--disable', '--fail', '--location', '--proto', '=https',
                    '--proto-redir', '=https', '--retry', '5', '--retry-delay', '2',
                    '--silent', '--show-error', '--output', str(destination), url], check=True)
            verify(staged, manifest)
            if target.exists():
                raise FileExistsError('Model destination appeared during setup; preserving it')
            staged.rename(target)
    shutil.copyfile(MANIFEST, vendor / MANIFEST.name)
    license_name = 'parakeet-tdt-0.6b-v2-coreml.LICENSE.txt'
    shutil.copyfile(REPO / 'models' / license_name, vendor / license_name)
    print('PASS: approved model is staged for offline packaging')

if __name__ == '__main__':
    main()
