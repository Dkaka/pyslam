#!/usr/bin/env bash
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

#echo "usage: ./${0##*/} <env-name>"

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

export ENV_NAME="${1:-pyslam}"  # get the first input if any, otherwise use 'pyslam' as default name
export PYSLAM_PYTHON_VERSION="${2:-3.11.9}"  # Default Python version

# ====================================================

# On macOS/Apple Silicon, default to arm64 packages unless the caller overrides
if [[ "$OSTYPE" == darwin* ]]; then
    export CONDA_SUBDIR=${CONDA_SUBDIR:-osx-arm64}
fi

print_blue '================================================'
print_blue "Creating Conda Environment: $ENV_NAME"
print_blue '================================================'

# check that conda is activated 
if ! command -v conda &> /dev/null ; then
    print_red "ERROR: Conda could not be found! Did you installe/activate conda?"
    exit 1
fi

#ubuntu_version=$(lsb_release -rs | cut -d. -f1)

conda install -n base -y conda-anaconda-tos
conda config --set plugins.auto_accept_tos yes || export CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2
conda config --add channels conda-forge
conda config --set channel_priority strict

conda update conda -y

# Use the libmamba solver for the (large) solves below: the classic solver can take tens of minutes.
# It is conda's default since 23.10, but older installs or a `solver: classic` in ~/.condarc still use
# the classic one. The option is passed per command, so the user's conda configuration is not changed.
CONDA_SOLVER_OPTS=""
if ! conda list -n base 2>/dev/null | grep -qE "^conda-libmamba-solver "; then
    conda install -n base -y conda-libmamba-solver || print_yellow "WARNING: could not install conda-libmamba-solver"
fi
if conda list -n base 2>/dev/null | grep -qE "^conda-libmamba-solver " && conda create --help 2>/dev/null | grep -q -- "--solver"; then
    CONDA_SOLVER_OPTS="--solver=libmamba"
else
    print_yellow "WARNING: the libmamba solver is not available: the environment solve may be slow"
fi


if conda env list | grep -E "^[[:space:]]*$ENV_NAME[[:space:]]" > /dev/null; then
    print_yellow "Conda environment $ENV_NAME already exists."
else 
    print_blue "Creating conda virtual environment $ENV_NAME with python version $PYSLAM_PYTHON_VERSION"
    conda create $CONDA_SOLVER_OPTS -yn "$ENV_NAME" python="$PYSLAM_PYTHON_VERSION" || { print_red "ERROR: conda create failed"; exit 1; }
fi

# on first run
if [ -z "$CONDA_PREFIX" ]; then
    CONDA_PREFIX=$(conda info --base)
fi
. "$CONDA_PREFIX"/bin/activate base   # from https://community.anaconda.cloud/t/unable-to-activate-environment-prompted-to-run-conda-init-before-conda-activate-but-it-doesnt-work/68677/10

# activate created env  
. "$SCRIPTS_DIR/pyenv-conda-activate.sh"

# Check if the current conda environment is "pyslam"
if [ "$CONDA_DEFAULT_ENV" != "$ENV_NAME" ]; then
    print_red "ERROR: The current conda environment is not '$ENV_NAME'. Please activate the '$ENV_NAME' environment and try again."
    exit 1
fi

PYTHON_EXE=$(get_python_exe)
ensure_pip "$PYTHON_EXE" || exit 1
# NOTE: these are the "system" packages that are needed within conda to build code from source
if [[ "$OSTYPE" == darwin* ]]; then
    # macOS: use clang from Xcode; avoid Linux-only packages
    conda install $CONDA_SOLVER_OPTS -y -c conda-forge \
        pkg-config cmake "eigen=5.0.1" suitesparse lapack openblas \
        tbb tbb-devel libpng libtiff zlib libjpeg-turbo freetype \
        ffmpeg glew glfw boost \
        'libopencv[version=">=4.12,<5",build="qt6*"]' 'py-opencv[version=">=4.12,<5",build="qt6*"]' \
        pyside6 "pytorch>=2.12" torchvision faiss-cpu "numpy<2" || { print_red "ERROR: conda install of the build packages failed"; exit 1; }
else
    conda install $CONDA_SOLVER_OPTS -y -c conda-forge \
        pkg-config \
        glew \
        cmake \
        suitesparse \
        lapack \
        glew glfw mesa-libgl-devel-cos7-x86_64 \
        libtiff zlib libjpeg-turbo "eigen=5.0.1" tbb libpng \
        x264 "ffmpeg>=6,<8" libva \
        freetype cairo \
        pygobject gtk2 gtk3 glib xorg-xorgproto \
        libwebp expat \
        compilers gcc_linux-64 gxx_linux-64 tbb tbb-devel \
        boost libboost-devel openblas \
        'libopencv[version=">=4.12,<5",build="qt6*"]' 'py-opencv[version=">=4.12,<5",build="qt6*"]' \
        pyside6 faiss-cpu "numpy<2" || { print_red "ERROR: conda install of the build packages failed"; exit 1; }
fi

# Install the Python packages after the conda packages, so that conda does not replace pip-installed
# ones (e.g. numpy). numpy<2 is pinned on the conda side too (libopencv would pull numpy 2).
# OpenCV comes from conda-forge (C++ libs for the C++ core, and cv2 via py-opencv): it registers the
# opencv-python(-headless) dist-infos, so pip does not install another cv2 over it. The qt6 build is
# pinned because the default solve can pick the headless one, which has no cv2.imshow.
# OpenCV 4 only: orbslam2_features needs find_package(OpenCV 4). SURF (non-free) is not available.
# The Qt bindings for pyqtgraph are PySide6 from conda-forge, on the same qt6-main as OpenCV, so one Qt
# is loaded. With PyQt5 (Qt5) next to OpenCV's Qt6, macOS segfaults when both show a window (duplicate
# Objective-C classes), and on Linux pip's PyQt5 wheel loads the system glib, which breaks conda's cv2.
# torch is installed before `pip install -e .`, which would otherwise pull the newest torch wheel:
# - macOS: from conda-forge (above; it includes MPS). pip's wheel bundles its own libomp, which clashes
#   with conda's (used by numpy/OpenBLAS and suitesparse) and aborts with "OMP: Error #15".
# - Linux: pip wheels matching the GPU (see install_pip3_torch.sh); the newest ones drop older GPUs.
"$PYTHON_EXE" -m pip install --upgrade pip setuptools wheel build || exit 1
"$SCRIPTS_DIR"/install_pip3_torch.sh || { print_red "ERROR: torch installation failed"; exit 1; }
"$PYTHON_EXE" -m pip install -e . || { print_red "ERROR: pip install -e . failed"; exit 1; }
# Fail early on conflicting native runtimes (e.g. two OpenMP libraries) rather than at the first run.
"$PYTHON_EXE" -c "import numpy, cv2, torch" || { print_red "ERROR: 'import numpy, cv2, torch' fails in the new environment"; exit 1; }

cd "$STARTING_DIR"

# To activate this environment, use
#   $ conda activate pyslam
# To deactivate an active environment, use
#   $ conda deactivate
