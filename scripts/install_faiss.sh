#!/usr/bin/env bash
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

ROOT_DIR="$SCRIPT_DIR_/.."

# ====================================================
# import the bash utils 
. "$ROOT_DIR"/bash_utils.sh 

cd "$ROOT_DIR" 

# ====================================================


PYTHON_EXE=${PYTHON_EXE:-$(get_python_exe)}

# faiss (used by the loop-closure database). Keep an existing one: e.g. conda-forge faiss-cpu from
# pyenv-conda-create.sh, which registers as dist "faiss", so `pip show faiss-cpu` does not see it. A pip
# wheel installed over it would mix files in site-packages/faiss (and on macOS bring a second libomp).
# The GPU wheel is opt-in (FAISS_GPU=1): it replaces the installed faiss, and not every GPU is supported.
if [[ "${FAISS_GPU:-0}" == 1 ]]; then
    if "$PYTHON_EXE" -m pip index versions faiss-gpu-cu12 >/dev/null 2>&1; then
        echo "Installing faiss-gpu-cu12 (FAISS_GPU=1)..."
        "$PYTHON_EXE" -m pip uninstall -y faiss faiss-cpu || true
        "$PYTHON_EXE" -m pip install faiss-gpu-cu12 || exit 1
    else
        print_red "ERROR: faiss-gpu-cu12 is not available for this Python/platform"
        exit 1
    fi
elif "$PYTHON_EXE" -c "import faiss" 2>/dev/null; then
    echo "faiss $("$PYTHON_EXE" -c 'import faiss; print(faiss.__version__)') is already installed"
else
    echo "Installing faiss-cpu..."
    "$PYTHON_EXE" -m pip install faiss-cpu || exit 1
fi
