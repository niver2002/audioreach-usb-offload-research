#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <kernel_source_dir>" >&2
  exit 1
fi

KERNEL_SRC="$1"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches"

if [[ ! -d "$KERNEL_SRC" ]]; then
  echo "Kernel source dir not found: $KERNEL_SRC" >&2
  exit 1
fi

if [[ ! -d "$PATCH_DIR" ]]; then
  echo "Patch dir not found: $PATCH_DIR" >&2
  exit 1
fi

mapfile -t PATCHES < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)
if [[ ${#PATCHES[@]} -eq 0 ]]; then
  echo "No patches found in: $PATCH_DIR" >&2
  exit 1
fi

echo "[1/2] Checking patch applicability..."
for p in "${PATCHES[@]}"; do
  echo "  - $p"
  git -C "$KERNEL_SRC" apply --check "$p"
done

echo "[2/2] Applying patches..."
for p in "${PATCHES[@]}"; do
  echo "  - $p"
  git -C "$KERNEL_SRC" apply "$p"
done

echo "Patch apply complete. Changed files:"
git -C "$KERNEL_SRC" status --short
