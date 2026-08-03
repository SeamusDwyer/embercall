#!/bin/bash
# Download and install GUT addon for running tests.
# Run once after cloning the repo.

set -e

GUT_VERSION="${GUT_VERSION:-v9.7.1}"
GUT_URL="https://github.com/bitwes/Gut/archive/refs/tags/${GUT_VERSION}.zip"
GUT_DIR="addons/gut"
TMP_ZIP="/tmp/gut_${GUT_VERSION}.zip"

if [ -d "$GUT_DIR" ] && [ -f "$GUT_DIR/gut_cmdln.gd" ]; then
    echo "GUT already installed at $GUT_DIR"
    exit 0
fi

echo "Downloading GUT ${GUT_VERSION}..."
curl -sL "$GUT_URL" -o "$TMP_ZIP"

echo "Extracting..."
python3 -c "
import zipfile, os
with zipfile.ZipFile('$TMP_ZIP', 'r') as z:
    namespace = z.namelist()[0].split('/')[0]
    for n in z.namelist():
        if n.startswith(f'{namespace}/addons/gut/'):
            target = n.replace(f'{namespace}/', '')
            if n.endswith('/'):
                os.makedirs(target, exist_ok=True)
            else:
                z.extract(n, '/tmp/gut_extract')
                os.makedirs(os.path.dirname(target), exist_ok=True)
                os.rename(f'/tmp/gut_extract/{n}', target)
"
rm -f "$TMP_ZIP"
rm -rf /tmp/gut_extract

echo "GUT ${GUT_VERSION} installed to $GUT_DIR"
echo "Verify: godot --headless --path . --import --quit"
