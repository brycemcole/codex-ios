#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
name=${1:-}
if [ -z "$name" ]; then
    echo "usage: build-agent.sh <name> [version]" >&2
    exit 1
fi
conf="$repo_root/compat/agents/$name.conf"
test -f "$conf"
. "$conf"

tag_prefix=${AGENT_TAG_PREFIX:-}
src_subdir=${AGENT_SRC_SUBDIR:-}
bin_name=${AGENT_BIN_NAME:-$name}
patch_prefix=${AGENT_PATCH_PREFIX:-patches/$name-ios}
clone_dir="$repo_root/.build/$name"
version=${2:-}

if [ ! -d "$clone_dir/.git" ]; then
    git clone "$AGENT_REPO_URL" "$clone_dir"
fi
git -C "$clone_dir" fetch --tags origin
git -C "$clone_dir" reset --hard HEAD
git -C "$clone_dir" clean -fd

if [ -z "$version" ]; then
    pattern="${tag_prefix}*"
    [ -n "$tag_prefix" ] || pattern='*'
    version=$(git ls-remote --tags "$AGENT_REPO_URL" "$pattern" \
        | sed 's/.*refs\/tags\///' \
        | grep -v '\^{}' \
        | grep -vE '\-(alpha|beta|rc)' \
        | sed "s/^${tag_prefix}//" \
        | grep '^[0-9]' \
        | sort -V | tail -1)
    if [ -z "$version" ]; then
        echo "no stable tags found for $AGENT_REPO_URL" >&2
        exit 1
    fi
fi

tag="$tag_prefix$version"
echo "building $name $tag"
git -C "$clone_dir" checkout --detach "$tag"
git -C "$clone_dir" reset --hard "$tag"

if [ -f "$repo_root/$patch_prefix-$version.patch" ]; then
    patch="$repo_root/$patch_prefix-$version.patch"
else
    base=$(ls "$repo_root/$patch_prefix"-*.patch 2>/dev/null | sort -V | tail -1 || true)
    if [ -z "$base" ]; then
        echo "no patch for $name ($patch_prefix-*.patch), refusing to build unpatched" >&2
        exit 1
    fi
    patch="$base"
    echo "no $version-specific patch, falling back to $(basename "$base")"
fi

if git -C "$clone_dir" apply --check "$patch" 2>/dev/null; then
    git -C "$clone_dir" apply "$patch"
    echo "patch applied cleanly"
elif git -C "$clone_dir" apply -3 "$patch" >/dev/null 2>&1; then
    echo "patch applied with 3-way merge, review $clone_dir for conflicts"
else
    if git -C "$clone_dir" ls-files -u | grep -q .; then
        echo "patch conflicts in $clone_dir, resolve then git add and re-run" >&2
        exit 1
    fi
    echo "patch does not apply to $tag, resolve manually in $clone_dir" >&2
    exit 1
fi

CODEX_IOS_ARCH=armv7 \
AGENT_SRC_SUBDIR="$src_subdir" \
AGENT_BIN_NAME="$bin_name" \
    "$repo_root/scripts/build-codex.sh"

CODEX_IOS_VERSION="$version" \
CODEX_IOS_BUILD_REV="${CODEX_IOS_BUILD_REV:-1}" \
AGENT_PKG_ID="${AGENT_PKG_ID:-com.brycemcole.$name-ios-armv7}" \
AGENT_PKG_NAME="${AGENT_PKG_NAME:-$name for iPhone 4S}" \
AGENT_PKG_DESC="${AGENT_PKG_DESC:-Native $name CLI for jailbroken armv7 iOS 9 devices}" \
AGENT_PKG_CONFLICTS="${AGENT_PKG_CONFLICTS:-}" \
AGENT_BIN_NAME="$bin_name" \
    "$repo_root/scripts/package-armv7.sh"

echo "done: dist/armv7/${AGENT_PKG_ID:-com.brycemcole.$name-ios-armv7}_${version}-1_iphoneos-arm.deb"
