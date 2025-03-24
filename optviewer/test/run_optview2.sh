#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")" || exit 1

echo "Running make..."
make

echo "Running optview2..."
#python3 ../opt-viewer.py --collect-opt-success --open-browser --output-dir ./out --source-dir ./ ./out
python3 ../opt-viewer.py --open-browser --output-dir ./out --source-dir ./ ./out
