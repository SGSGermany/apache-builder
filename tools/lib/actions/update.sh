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
}

action_exec() {
    # build and import image
    __call build
    __call import

    # remember whether to restart service
    local RESTART_UNIT=""
    if unit_active "$UNIT.service"; then
        RESTART_UNIT="y"
    fi

    # update subids (if enabled)
    if [ -n "$MANAGE_SUBIDS" ]; then
        __call subids
    fi

    # create unit
    __call create-unit

    # restart service
    if [ -n "$RESTART_UNIT" ]; then
        __call unit-restart
    fi
}
