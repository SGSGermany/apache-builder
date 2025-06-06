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
    echo + "UNIT=${UNIT@Q}" >&2
}

action_exec() {
    check_unit "$UNIT"

    # since we're using Quadlet, Systemd can't enable or disable the generated Systemd unit
    # we thus just comment the '[Install]' section inside the Quadlet Systemd unit file
    local UNIT_PATH_QUADLET="$(__quadlet_dir)/$UNIT.container"

    check_path "Invalid Quadlet Systemd unit ${UNIT@Q} at" "$UNIT_PATH_QUADLET" -r -w

    echo + "grep -q -Fx '#[Install]' $(quote "$UNIT_PATH_QUADLET")" >&2
    if grep -q -Fx '#[Install]' "$UNIT_PATH_QUADLET"; then
        # unit is already disabled, nothing to do
        return 0
    elif ! grep -q -Fx '[Install]' "$UNIT_PATH_QUADLET"; then
        # unit can't be disabled, bail with error
        echo "Invalid Quadlet Systemd unit ${UNIT@Q} at ${UNIT_PATH_SYSTEMD@Q}: Unit has no '[Install]' section" >&2
        return 1
    fi

    cmd gawk -i inplace '/\[.+\]/ { found=0 } /\[Install\]/ { found=1 }
        found && !/^(\s*|#.*)$/ { print "#" $0 } !found || /^(\s*|#.*)$/ { print }' "$UNIT_PATH_QUADLET"

    # reload systemd daemon
    __systemctl daemon-reload
}
