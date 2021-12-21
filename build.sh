#!/bin/bash
# apache-builder
# A container to build Apache containers.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C

cmd() {
    echo + "$@"
    "$@"
    return $?
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

echo + "CONTAINER=\"\$(buildah from $BASE_IMAGE)\""
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

cmd buildah run "$CONTAINER" -- \
    pacman -Syu --noconfirm

cmd buildah run "$CONTAINER" -- \
    pacman -Sy --noconfirm podman buildah skopeo rsync jq

cmd buildah run "$CONTAINER" -- \
    sh -c "pacman -Qdtq | xargs -d'\n' -r -- pacman -Rs --noconfirm"

cmd buildah run "$CONTAINER" -- \
    groupadd -g 65536 apache-builder

cmd buildah run "$CONTAINER" -- \
    useradd -u 65536 -s "/sbin/nologin" \
        -g apache-builder -N \
        -d "/var/local/apache-builder" -M \
        apache-builder

cmd buildah run "$CONTAINER" -- \
    chown -R -h apache-builder:apache-builder "/var/local/apache-builder"

cmd buildah config \
    --env BUILDAH_ISOLATION="chroot" \
    "$CONTAINER"

cmd buildah config \
    --volume "/etc/apache-builder" \
    --volume "/var/local/apache-builder/archives" \
    "$CONTAINER"

cmd buildah config \
    --workingdir "/var/local/apache-builder" \
    --entrypoint '[ "/entrypoint.sh" ]' \
    --cmd "apache-builder" \
    --user "apache-builder" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done
