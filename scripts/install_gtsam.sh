#!/usr/bin/env bash
# Author: Luigi Freda 
# Author: Luigi Freda 
# This file is part of https://github.com/luigifreda/pyslam

#set -e

SCRIPT_DIR_=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ) # get script dir
SCRIPT_DIR_=$(readlink -f $SCRIPT_DIR_)  # this reads the actual path if a symbolic directory is used

ROOT_DIR="$SCRIPT_DIR_/.."
SCRIPTS_DIR="$ROOT_DIR/scripts"

# ====================================================
# import the bash utils 
. "$ROOT_DIR"/bash_utils.sh 

# ====================================================

STARTING_DIR=`pwd`  
cd "$ROOT_DIR"  

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    version=$(lsb_release -a 2>&1)  # ubuntu version
else 
    version=$OSTYPE
    echo "OS: $version"
fi

# check if we have external options
EXTERNAL_OPTIONS=$@
if [[ -n "$EXTERNAL_OPTIONS" ]]; then
    echo "external option: $EXTERNAL_OPTIONS" 
fi

EXTERNAL_OPTIONS="$EXTERNAL_OPTIONS -DCMAKE_POLICY_VERSION_MINIMUM=3.5"


# Check if conda is installed
if command -v conda &> /dev/null; then
    echo "Conda is installed"
    CONDA_INSTALLED=true
else
    #echo "Conda is not installed"
    CONDA_INSTALLED=false
fi

# Check if pixi is activated
if [[ -n "$PIXI_PROJECT_NAME" ]]; then
    PIXI_ACTIVATED=true
    echo "Pixi environment detected: $PIXI_PROJECT_NAME"

    source "$SCRIPTS_DIR/pixi_python_config.sh"
else
    PIXI_ACTIVATED=false
fi

# ====================================================

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ubuntu_version=$(lsb_release -rs | cut -d. -f1)
else
    ubuntu_version=""
fi

# Check if CC is set and available, otherwise use default gcc
if command -v "$CC" &> /dev/null; then
    gcc_version=$($CC -dumpversion | cut -d. -f1)
elif command -v gcc &> /dev/null; then
    gcc_version=$(gcc -dumpversion | cut -d. -f1)
else
    print_red "Error: No C compiler found. Please install gcc or a equivalent compiler."
fi
echo "gcc_version: $gcc_version"

if [[ "$CONDA_INSTALLED" == true && "$ubuntu_version" == "20" && "$gcc_version" == 11 ]]; then
    print_blue "Setting GCC and G++ to version 9"
    export CC=/usr/bin/gcc-9
    export CXX=/usr/bin/g++-9
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Make sure we don't accidentally use a Linux cross-compiler or Linux sysroot from conda
    unset CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS SDKROOT CONDA_BUILD_SYSROOT CONDA_BUILD_CROSS_COMPILATION

    # Ask Xcode for the proper macOS SDK path (fallback to default if unavailable)
    MAC_SYSROOT=$(xcrun --show-sdk-path 2>/dev/null || echo "")

    MAC_OPTIONS="-DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++"

    echo "Using MAC_OPTIONS for cpp build: $MAC_OPTIONS"
fi

print_blue '================================================'
print_blue "Installing gtsam from source"
print_blue '================================================'

# Prefer the active conda/venv python (set by install_all_conda.sh via pyenv-activate.sh)
if [[ -n "$CONDA_PREFIX" && -x "$CONDA_PREFIX/bin/python" ]]; then
    PYTHON_EXE="$CONDA_PREFIX/bin/python"
else
    PYTHON_EXE=$(which python)
fi
echo "Using PYTHON_EXE: $PYTHON_EXE"

PYTHON_VERSION=$($PYTHON_EXE -c "import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")")

# GTSAM tag to build. thirdparty/gtsam.patch, thirdparty/gtsam_factors and the C++ core
# (optimizer_gtsam.cpp) are written against this version, so they must be updated together.
GTSAM_TAG="4.2a9"

# The nproc alias in bash_utils.sh is not expanded in non-interactive scripts.
if [[ "$OSTYPE" == darwin* ]]; then
    NUM_CORES=$(sysctl -n hw.logicalcpu)
else
    NUM_CORES=$(nproc)
fi


WITH_MARCH_NATIVE=ON
if [[ "$OSTYPE" == darwin* ]]; then
    WITH_MARCH_NATIVE=OFF
fi
if [[ "$PIXI_ACTIVATED" == true ]]; then
    WITH_MARCH_NATIVE=OFF
fi
echo "WITH_MARCH_NATIVE: $WITH_MARCH_NATIVE"

# gtwrap (GTSAM Python bindings) needs pyparsing at build time (normally installed by install_pip3_packages.sh)
ensure_python_package "$PYTHON_EXE" "pyparsing>=2.4.6" pyparsing || exit 1

cd thirdparty
if [ ! -d gtsam_local ]; then
    # Remove a partial checkout on failure, so that the next run starts from scratch
    # instead of silently building an unpatched or wrong version.
    # Shallow clone of just the tag: the full history is large and slow to fetch.
    if ! ( git clone --depth 1 --branch $GTSAM_TAG https://github.com/borglab/gtsam.git gtsam_local && \
           cd gtsam_local && \
           git apply ../gtsam.patch ); then
        print_red "Error: failed to fetch GTSAM $GTSAM_TAG or apply thirdparty/gtsam.patch"
        rm -rf gtsam_local
        exit 1
    fi
fi
cd gtsam_local
make_buid_dir
GTSAM_INSTALL_DIR="$(pwd -P)/install"
GTSAM_CONFIG_FILE="install/lib/cmake/GTSAM/GTSAMConfig.cmake"
TARGET_GTSAM_LIB="install/lib/libgtsam.so"
if [[ "$OSTYPE" == darwin* ]]; then
    TARGET_GTSAM_LIB="install/lib/libgtsam.dylib"
fi

# Print the (physical) directory of the libgtsam that a gtsam python extension module loads.
function linked_libgtsam_dir(){
    local lib
    if [[ "$OSTYPE" == darwin* ]]; then
        lib=$(otool -L "$1" 2>/dev/null | awk '/libgtsam\./ {print $1; exit}')
    else
        lib=$(ldd "$1" 2>/dev/null | awk '/libgtsam\.so/ {print $3; exit}')
    fi
    if [[ -n "$lib" && -d "$(dirname "$lib")" ]]; then
        (cd "$(dirname "$lib")" && pwd -P)
    fi
}

# The gtsam python module must load the *installed* libgtsam, the same one that gtsam_factors
# and the C++ core link. `make python-install` pip-installs from the build tree, so the build must
# use the install paths (CMAKE_BUILD_WITH_INSTALL_RPATH below); otherwise the build-tree libgtsam
# is loaded as well and two copies of GTSAM end up in the same process.
# Rebuild if the library is missing or the build-tree python module was built the old way.
BUILD_GTSAM_PY_MODULE=$(ls build/python/gtsam/gtsam*.so 2>/dev/null | head -1)
NEED_GTSAM_BUILD=false
if [[ ! -f "$TARGET_GTSAM_LIB" || ! -f "$GTSAM_CONFIG_FILE" || -z "$BUILD_GTSAM_PY_MODULE" ]]; then
    NEED_GTSAM_BUILD=true
elif [[ "$(linked_libgtsam_dir "$BUILD_GTSAM_PY_MODULE")" != "$GTSAM_INSTALL_DIR/lib" ]]; then
    echo "The gtsam python module in build/ does not link $GTSAM_INSTALL_DIR/lib: rebuilding GTSAM"
    NEED_GTSAM_BUILD=true
fi

if [[ "$NEED_GTSAM_BUILD" == true ]]; then
	cd build
    # NOTE: gtsam has some issues when compiling with march=native option!
    # https://groups.google.com/g/gtsam-users/c/jdySXchYVQg
    # https://bitbucket.org/gtborg/gtsam/issues/414/compiling-with-march-native-results-in 
    GTSAM_OPTIONS="-DGTSAM_USE_SYSTEM_EIGEN=ON -DGTSAM_BUILD_WITH_MARCH_NATIVE=$WITH_MARCH_NATIVE -DGTSAM_BUILD_PYTHON=ON -DGTSAM_BUILD_TESTS=OFF -DGTSAM_BUILD_EXAMPLES=OFF" 
    if [[ "$version" == *"24.04"* ]] ; then
        # Ubuntu 24.04 requires CMake 3.22 or higher
        GTSAM_OPTIONS+=" -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    fi
    # Pin the interpreter: with GTSAM_PYTHON_VERSION set, GTSAM skips its own Python lookup and
    # the wrapper (pybind11) uses PYTHON_EXECUTABLE, which is also what `make python-install` runs.
    GTSAM_OPTIONS+=" -DGTSAM_THROW_CHEIRALITY_EXCEPTION=OFF -DGTSAM_PYTHON_VERSION=$PYTHON_VERSION"
    GTSAM_OPTIONS+=" -DPYTHON_EXECUTABLE=$PYTHON_EXE -DPython_EXECUTABLE=$PYTHON_EXE -DPython3_EXECUTABLE=$PYTHON_EXE"
    if [[ "$OSTYPE" == darwin* ]]; then
        GTSAM_OPTIONS+=" -DGTSAM_WITH_TBB=OFF"
    fi
    # Build with the install paths (install names on macOS, RPATH on Linux), so that the python
    # module installed from the build tree loads the installed libgtsam (see above).
    GTSAM_OPTIONS+=" -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH=$GTSAM_INSTALL_DIR/lib -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
    echo GTSAM_OPTIONS: $GTSAM_OPTIONS
    cmake .. -DCMAKE_INSTALL_PREFIX="$GTSAM_INSTALL_DIR" -DCMAKE_BUILD_TYPE=Release $GTSAM_OPTIONS $EXTERNAL_OPTIONS $MAC_OPTIONS || { print_red "Error: GTSAM cmake configure failed"; exit 1; }
	make -j $NUM_CORES || { print_red "Error: GTSAM build failed"; exit 1; }
    make install || { print_red "Error: GTSAM install failed"; exit 1; }
    cd ..
fi

# Install the gtsam python package into $PYTHON_EXE unless it already has this version and
# loads the installed libgtsam. This runs even when the C++ library is already built, so that a
# recreated python environment gets the package back. A different gtsam (e.g. a pip wheel) is replaced.
function installed_gtsam_py_module(){
    $PYTHON_EXE -c "import gtsam, glob, os; print(glob.glob(os.path.join(os.path.dirname(gtsam.__file__), 'gtsam*.so'))[0])" 2>/dev/null
}
INSTALLED_GTSAM_PY_VERSION=$($PYTHON_EXE -c "import gtsam, importlib.metadata as m; print(m.version('gtsam'))" 2>/dev/null)
INSTALLED_GTSAM_PY_LIB_DIR=$(linked_libgtsam_dir "$(installed_gtsam_py_module)")
if [[ "$INSTALLED_GTSAM_PY_VERSION" != "$GTSAM_TAG" || "$INSTALLED_GTSAM_PY_LIB_DIR" != "$GTSAM_INSTALL_DIR/lib" ]]; then
    echo "Installing gtsam python package (found: '${INSTALLED_GTSAM_PY_VERSION:-none}' linking '${INSTALLED_GTSAM_PY_LIB_DIR:-none}', expected: $GTSAM_TAG linking $GTSAM_INSTALL_DIR/lib)"
    ( cd build && make python-install ) || { print_red "Error: GTSAM python install failed"; exit 1; }
fi
if ! $PYTHON_EXE -c "import gtsam" ; then
    print_red "Error: 'import gtsam' fails with $PYTHON_EXE"
    exit 1
fi
INSTALLED_GTSAM_PY_LIB_DIR=$(linked_libgtsam_dir "$(installed_gtsam_py_module)")
if [[ "$INSTALLED_GTSAM_PY_LIB_DIR" != "$GTSAM_INSTALL_DIR/lib" ]]; then
    print_red "Error: the gtsam python module loads libgtsam from '$INSTALLED_GTSAM_PY_LIB_DIR' instead of $GTSAM_INSTALL_DIR/lib"
    exit 1
fi

echo current folder: $(pwd)

cd "$ROOT_DIR"

print_blue '================================================'
print_blue "Building gtsam_factors"
print_blue '================================================'

cd thirdparty
cd gtsam_factors
./build.sh $EXTERNAL_OPTIONS -DWITH_MARCH_NATIVE=$WITH_MARCH_NATIVE || { print_red "Error: gtsam_factors build failed"; exit 1; }

cd "$ROOT_DIR"

cd "$STARTING_DIR"