#!/usr/bin/env bash
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

#N.B: this script allows to build the C++ core of pySLAM

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

ROOT_DIR="$SCRIPT_DIR_"
SCRIPTS_DIR="$ROOT_DIR/scripts"

# ====================================================
# import the bash utils 
. "$ROOT_DIR"/bash_utils.sh 

# ====================================================

STARTING_DIR=`pwd`
cd "$ROOT_DIR"

#set -e

print_blue '================================================'
print_blue "Building pySLAM C++ core"
print_blue '================================================'

cd "$ROOT_DIR/pyslam/slam/cpp"
# Remove the previously built module first: if this build fails, a stale cpp_core from older
# sources must not stay importable and look like a successful build.
rm -f lib/cpp_core*.so lib/cpp_core*.pyd
./build.sh || { print_red "ERROR: building the pySLAM C++ core failed (see the messages above)"; cd "$STARTING_DIR"; exit 1; }
if ! compgen -G "lib/cpp_core*.so" >/dev/null && ! compgen -G "lib/cpp_core*.pyd" >/dev/null; then
    print_red "ERROR: the build finished but lib/cpp_core*.so was not produced"
    cd "$STARTING_DIR"
    exit 1
fi

cd "$STARTING_DIR"