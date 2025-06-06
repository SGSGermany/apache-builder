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
    if [ -n "$AUTO_UPDATE" ]; then
        echo + "BASE_IMAGE=${BASE_IMAGE@Q}" >&2
        echo + "IMAGE=${IMAGE@Q}" >&2
        echo + "TAGS=${TAGS@Q}" >&2

        echo + "UNIT=${UNIT@Q}" >&2
        echo + "UNIT_TEMPLATE=${UNIT_TEMPLATE@Q}" >&2
        echo + "UNIT_MANAGER=${UNIT_MANAGER@Q}" >&2
        echo + "UNIT_ENABLED=${UNIT_ENABLED@Q}" >&2

        echo + "BUILDER_USER=${BUILDER_USER@Q}" >&2
        echo + "BUILDER_IMAGE=${BUILDER_IMAGE@Q}" >&2
        echo + "BUILDER_CONTAINER=${BUILDER_CONTAINER@Q}" >&2
        echo + "BUILDER_CONFIG=${BUILDER_CONFIG@Q}" >&2
        echo + "ARCHIVES_PATH=${ARCHIVES_PATH@Q}" >&2

        echo + "CONTAINER=${CONTAINER@Q}" >&2
        echo + "CONTAINER_USERNS=${CONTAINER_USERNS@Q}" >&2
        echo + "CONTAINER_NETWORK=${CONTAINER_NETWORK@Q}" >&2
        echo + "CONTAINER_HOSTNAME=${CONTAINER_HOSTNAME@Q}" >&2
        echo + "CONTAINER_PUBLISH_PORTS=( ${CONTAINER_PUBLISH_PORTS[@]@Q} )" >&2

        echo + "HOST_UID_MAP=( ${HOST_UID_MAP[@]@Q} )" >&2
        echo + "HOST_GID_MAP=( ${HOST_GID_MAP[@]@Q} )" >&2

        echo + "MANAGE_SUBIDS=${MANAGE_SUBIDS@Q}" >&2
        if [ -n "$MANAGE_SUBIDS" ]; then
            echo + "STATIC_SUBUIDS=( ${STATIC_SUBUIDS[@]@Q} )" >&2
            echo + "STATIC_SUBGIDS=( ${STATIC_SUBGIDS[@]@Q} )" >&2
        fi
    fi

    echo + "AUTO_UPDATE=${AUTO_UPDATE@Q}" >&2
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
        if unit_active "$UNIT.service"; then
            exit 0
        fi

        # import existing image, if necessary
        if ! __call exists; then
            __call import
        fi

        # create unit file from existing image, if necessary
        if ! unit_loaded "$UNIT.service"; then
            __call create-unit
        fi
    fi

    # enable unit and start service if it isn't running already (if autostart is enabled),
    # or disable unit, but don't stop an already running service
    # a previously running service thus keeps running (possibly after a restart)
    if [ -n "$UNIT_ENABLED" ]; then
        __call unit-enable

        if [ -n "$AUTO_START" ] && ! unit_active "$UNIT.service"; then
            __call unit-start
        fi
    else
        __call unit-disable
    fi
}
