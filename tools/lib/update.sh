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
    # build and import image
    __call build
    __call import

    # stop service
    local START_UNIT=""
    if unit_active "$UNIT"; then
        START_UNIT="yes"
        __call unit-stop
    fi

    # create and enable unit
    __call create-unit

    # start service, unless the service wasn't running
    if [ -n "$START_UNIT" ]; then
        __call unit-start
    fi
}
