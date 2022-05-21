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

action_info() {
    echo + "IMAGE=${IMAGE@Q}" >&2
    echo + "UNIT=${UNIT@Q}" >&2
    echo + "UNIT_TEMPLATE=${UNIT_TEMPLATE@Q}" >&2
    echo + "BUILDER_USER=${BUILDER_USER@Q}" >&2
    echo + "BUILDER_IMAGE=${BUILDER_IMAGE@Q}" >&2
    echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2
    echo + "CONFIG_PATH=${CONFIG_PATH@Q}" >&2
}

action_exec() {
    # check whether auto updates are enabled
    if [ -z "$AUTO_UPDATE" ]; then
        echo "Unable to auto update Podman image '$IMAGE': Auto updates have been disabled" >&2
        exit 1
    fi

    # update image, if necessary
    # remove old images first, thus keeping the latest and the new image
    if ! __call check-updates; then
        __call clean

        __call update
    else
        # image is up to date and container is running, nothing to do
        if unit_active "$UNIT"; then
            exit 0
        fi

        # import existing image, if necessary
        if ! __call exists; then
            __call import
        fi

        # create unit file from existing image, if necessary
        if ! unit_loaded "$UNIT"; then
            __call create-unit
        fi
    fi

    # enable unit and start service if it isn't running already,
    # or disable unit, but don't stop an already running service
    if [ -n "$UNIT_ENABLED" ]; then
        __call unit-enable

        if ! unit_active "$UNIT"; then
            __call unit-start
        fi
    else
        __call unit-disable
    fi
}
