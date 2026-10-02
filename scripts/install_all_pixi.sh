#!/usr/bin/env bash
# This file is part of https://github.com/luigifreda/pyslam
#
# pySLAM installation with pixi: see docs/PIXI.md.
#
# With pixi the Python environment comes from pixi.toml / pixi.lock, so this script only builds
# pySLAM's native modules and checks them (the tasks `build` and `check`). It installs no packages:
# no apt, no sudo, no pip. The optional models are installed per level, on request:
#   pixi run models                            (default level: learned features, place recognition)
#   pixi run -e depth models-depth
#   pixi run -e semantics models-semantics
#   pixi run -e full models-scene3d
#
# usage (either one):  pixi run build && pixi run check
#                      pixi shell, then ./install_all.sh   (which calls this script)

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used
ROOT_DIR="$SCRIPT_DIR_/.."

. "$ROOT_DIR"/bash_utils.sh

# pixi itself: on the PATH, or the one that started this environment (PIXI_EXE)
PIXI_BIN="${PIXI_EXE:-pixi}"
if ! command -v "$PIXI_BIN" &> /dev/null; then
    print_red "ERROR: pixi not found. Install it first: see docs/PIXI.md"
    return 1 2>/dev/null || exit 1
fi

STARTING_DIR=`pwd`
cd "$ROOT_DIR"

# Use the level of the active pixi shell, if any (default otherwise)
PIXI_ENV_OPTION=""
if [[ -n "$PIXI_ENVIRONMENT_NAME" ]]; then
    PIXI_ENV_OPTION="-e $PIXI_ENVIRONMENT_NAME"
fi

print_blue '================================================'
print_blue "Building and checking pySLAM with pixi (level: ${PIXI_ENVIRONMENT_NAME:-default})"
print_blue '================================================'

"$PIXI_BIN" run $PIXI_ENV_OPTION build && "$PIXI_BIN" run $PIXI_ENV_OPTION check
status=$?

cd "$STARTING_DIR"
if [ $status -ne 0 ]; then
    print_red "ERROR: the pixi build or its check failed (see above)"
    return $status 2>/dev/null || exit $status
fi
print_green "pySLAM is built. Install the optional models with 'pixi run models' (see docs/PIXI.md)."
