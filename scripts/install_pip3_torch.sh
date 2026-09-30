#!/usr/bin/env bash
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

SCRIPT_DIR_=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

ROOT_DIR="$SCRIPT_DIR_/.."

# ====================================================
# import the bash utils 
. "$ROOT_DIR"/bash_utils.sh 

cd "$ROOT_DIR" 

# ====================================================

#set -x
#set -e

PYTHON_EXE=$(get_python_exe)
PYTHON_ENV=$("$PYTHON_EXE" -c "import sys; print(sys.prefix)")
echo "PYTHON_ENV: $PYTHON_ENV"
echo "PYTHON_EXE: $PYTHON_EXE"

ensure_pip "$PYTHON_EXE" || exit 1

# Check if conda is installed
if command -v conda &> /dev/null; then
    CONDA_INSTALLED=true
else
    CONDA_INSTALLED=false
fi

# Check if pixi is activated
if [[ -n "$PIXI_PROJECT_NAME" ]]; then
    PIXI_ACTIVATED=true
else
    PIXI_ACTIVATED=false
fi

print_blue '================================================'
print_blue "Configuring and installing torch packages ..."

export WITH_PYTHON_INTERP_CHECK=ON  # in order to detect the correct python interpreter

# detect and configure CUDA 
. "$ROOT_DIR"/cuda_config.sh


if [[ "$OSTYPE" == darwin* ]]; then
    if [[ -n "$CONDA_PREFIX" ]] && conda list -p "$CONDA_PREFIX" 2>/dev/null | grep -qE "^pytorch "; then
        # conda env: torch comes from conda-forge (pyenv-conda-create.sh). A pip torch wheel would
        # bring its own libomp next to conda's and abort with "OMP: Error #15".
        print_green "torch is installed from conda-forge: not installing a pip torch wheel"
    else
        # torch 2.1/2.4 headers fail to compile detectron2 on recent macOS/Xcode; 2.6+ works.
        # torch==2.2.0 causes some segmentation faults on older mac setups.
        "$PYTHON_EXE" -m pip install torch==2.6.0 torchvision==0.21.0 || exit 1
    fi
else
    TARGET_TORCH_VERSION="2.9.1"
    TARGET_TORCHVISION_VERSION="0.24.1"

    # Choose the wheel from the GPU, not from the system CUDA toolkit: the wheels bundle their CUDA
    # runtime and only need a recent enough driver. The CUDA 12.8 wheels drop Pascal and older GPUs
    # (compute capability < 7.0) and need driver >= 570; the CUDA 12.6 wheels still support them.
    TORCH_WHEEL_FLAVOR=cpu
    if command -v nvidia-smi &> /dev/null; then
        GPU_MIN_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | sort -n | head -1)
        DRIVER_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1)
        if [[ -n "$GPU_MIN_CC" && -n "$DRIVER_MAJOR" ]]; then
            if awk "BEGIN{exit !($GPU_MIN_CC < 7.0)}" || (( DRIVER_MAJOR < 570 )); then
                TORCH_WHEEL_FLAVOR=cu126
            else
                TORCH_WHEEL_FLAVOR=cu128
            fi
        fi
        print_blue "GPU compute capability: ${GPU_MIN_CC:-unknown}, driver: ${DRIVER_MAJOR:-unknown}"
    fi
    print_green "Installing torch==$TARGET_TORCH_VERSION and torchvision==$TARGET_TORCHVISION_VERSION ($TORCH_WHEEL_FLAVOR)"
    "$PYTHON_EXE" -m pip install torch=="$TARGET_TORCH_VERSION" torchvision=="$TARGET_TORCHVISION_VERSION" \
        --index-url https://download.pytorch.org/whl/$TORCH_WHEEL_FLAVOR \
        --extra-index-url https://pypi.org/simple || { print_red "ERROR: torch installation failed"; exit 1; }
    if [[ "$TORCH_WHEEL_FLAVOR" != cpu ]]; then
        if ! "$PYTHON_EXE" -c "import torch; assert torch.cuda.is_available(); x = torch.ones(8, device='cuda'); assert float((x + x).sum()) == 16.0"; then
            print_yellow "WARNING: torch is installed but cannot run on this GPU: GPU features will fall back to CPU or be unavailable"
        fi
    fi
fi 

"$PYTHON_EXE" -m pip install "numpy<2"

