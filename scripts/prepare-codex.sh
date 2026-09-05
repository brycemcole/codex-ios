#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/.build/codex"
commit=be6e8eac029b183056b7e4402879f15d2c85f61b

mkdir -p "$repo_root/.build"
if [ ! -d "$source_dir/.git" ]; then
    git clone https://github.com/openai/codex.git "$source_dir"
fi

git -C "$source_dir" fetch --tags origin
git -C "$source_dir" checkout --detach "$commit"
git -C "$source_dir" reset --hard "$commit"
git -C "$source_dir" apply "$repo_root/patches/codex-ios-0.147.0.patch"
