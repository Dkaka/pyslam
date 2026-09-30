#!/usr/bin/env bash
# This file is part of https://github.com/luigifreda/pyslam
#
# Install optional pySLAM components ("extras") on request, on top of the core installation
# (pyenv-conda-create.sh + the core builds), instead of installing everything at once.
# Each extra fetches only the git submodules it needs, applies pySLAM's patches, downloads the
# model weights and then checks every component on the bundled test images (scripts/extras_check.py).
# It can be re-run safely: patches already applied and files already downloaded are skipped.
#
# usage: scripts/install_extra.sh --list
#        scripts/install_extra.sh <extra> [<extra> ...]      e.g. scripts/install_extra.sh features vpr

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

SCRIPTS_DIR="$SCRIPT_DIR_"
ROOT_DIR="$SCRIPT_DIR_/.."

# ====================================================
# import the bash utils
. "$ROOT_DIR"/bash_utils.sh

STARTING_DIR=`pwd`
cd "$ROOT_DIR"

# ====================================================

PYTHON_EXE=$(get_python_exe)

declare -A EXTRA_DESCRIPTIONS=(
    [features]="Learned local features and matchers: SuperPoint, LightGlue, XFeat, DISK, ALIKED, D2-Net, R2D2, Key.Net, HardNet, SOSNet, TFeat, L2-Net, LoFTR"
    [vpr]="Visual place recognition loop detectors: NetVLAD, CosPlace, EigenPlaces, MegaLoc, AlexNet"
)
EXTRAS_ORDER="features vpr"

function list_extras() {
    echo "Available extras:"
    for e in $EXTRAS_ORDER; do
        printf "  %-10s %s\n" "$e" "${EXTRA_DESCRIPTIONS[$e]}"
    done
}

# init_submodules <path> ...: fetch only the given git submodules (recursively)
function init_submodules() {
    print_blue "Fetching submodules: $*"
    git submodule update --init --recursive -- "$@" || { print_red "ERROR: could not fetch submodules: $*"; exit 1; }
}

# apply_patch <thirdparty dir> <patch file in thirdparty/>: apply unless it is already applied
function apply_patch() {
    local dir="$ROOT_DIR/thirdparty/$1" patch="$ROOT_DIR/thirdparty/$2"
    if git -C "$dir" apply --reverse --check "$patch" &>/dev/null; then
        echo "patch $2 already applied"
    elif git -C "$dir" apply --check "$patch" &>/dev/null; then
        git -C "$dir" apply "$patch" && echo "patch $2 applied" || { print_red "ERROR: could not apply $2"; exit 1; }
    else
        print_red "ERROR: $2 does not apply to thirdparty/$1 (local changes?)"
        exit 1
    fi
}

function install_features() {
    init_submodules thirdparty/superpoint thirdparty/LightGlue thirdparty/accelerated_features \
        thirdparty/disk thirdparty/d2net thirdparty/r2d2 thirdparty/keynet thirdparty/hardnet \
        thirdparty/SOSNet thirdparty/tfeat thirdparty/logpolar
    apply_patch d2net d2net.patch
    apply_patch r2d2 r2d2.patch
    apply_patch keynet keynet.patch
    apply_patch LightGlue lightglue.patch
    # D2-Net weights (the other models are downloaded by the check below, on first creation)
    if [ ! -f thirdparty/d2net/models/d2_ots.pth ]; then
        print_blue "Downloading the D2-Net model ..."
        ensure_python_package "$PYTHON_EXE" gdown gdown || exit 1
        make_dir thirdparty/d2net/models
        ( cd thirdparty/d2net/models && gdrive_download "12Uk95TjBT7VZSEitvm3B3XNK37Q_uU8T" "d2net.tar.xz" \
            && tar -xf d2net.tar.xz && rm d2net.tar.xz ) || { print_red "ERROR: could not download the D2-Net model"; exit 1; }
    fi
}

function install_vpr() {
    init_submodules thirdparty/vpr thirdparty/patch_netvlad
    apply_patch vpr vpr.patch
    apply_patch patch_netvlad patch_netvlad.patch
    # torch >= 2.13 asks "Do you trust this repository?" on the first torch.hub.load of a repo, which
    # a loop-detection child process cannot answer: trust the repos used by the VPR detectors.
    "$PYTHON_EXE" - <<'EOF' || exit 1
import os, torch
path = os.path.join(torch.hub.get_dir(), "trusted_list")
os.makedirs(os.path.dirname(path), exist_ok=True)
trusted = set(open(path).read().split()) if os.path.exists(path) else set()
new = [r for r in ("gmberton_cosplace", "gmberton_eigenplaces", "gmberton_MegaLoc") if r not in trusted]
if new:
    with open(path, "a") as f:
        f.write("".join(r + "\n" for r in new))
print("torch.hub trusted repos:", ", ".join(sorted(trusted | set(new))))
EOF
}

if [[ $# -eq 0 || "$1" == "--list" || "$1" == "-h" || "$1" == "--help" ]]; then
    echo "usage: $0 --list | <extra> [<extra> ...]"
    list_extras
    cd "$STARTING_DIR"
    [[ $# -eq 0 ]] && exit 1 || exit 0
fi

for extra in "$@"; do
    if [[ -z "${EXTRA_DESCRIPTIONS[$extra]}" ]]; then
        print_red "ERROR: unknown extra '$extra'"
        list_extras
        exit 1
    fi
done

FAILED=""
for extra in "$@"; do
    print_blue '================================================'
    print_blue "Installing extra '$extra': ${EXTRA_DESCRIPTIONS[$extra]}"
    print_blue '================================================'
    install_$extra
    print_blue "Checking '$extra' and downloading its model weights (first run can take a while) ..."
    "$PYTHON_EXE" "$SCRIPTS_DIR/extras_check.py" "$extra" || FAILED="$FAILED $extra"
done

cd "$STARTING_DIR"
if [[ -n "$FAILED" ]]; then
    print_red "Some components failed the check in:$FAILED (see above)"
    exit 1
fi
print_green "Installed: $*"
