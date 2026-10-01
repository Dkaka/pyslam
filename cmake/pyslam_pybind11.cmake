# Make a pySLAM module build against the bundled pybind11 (thirdparty/pybind11), never another copy.
#
# Every pySLAM Python module must use the same pybind11 version: modules share C++ types only if their
# pybind11 internals ABI matches (scripts/check_pybind11_abi.py checks it after the builds). Another
# pybind11 can be on the include path, e.g. conda's pytorch brings pybind11 headers into
# $CONDA_PREFIX/include. The bundled pybind11 target passes its include dir as -isystem, which is
# searched after any -I dir and, for the same dir, cancels a -I; so drop that and prepend the bundled
# include dir as a regular -I.
#
# Usage, after add_subdirectory(<bundled pybind11>):
#   include(<repo root>/cmake/pyslam_pybind11.cmake)
#   pyslam_use_bundled_pybind11(<bundled pybind11 source dir>)

function(pyslam_use_bundled_pybind11 pybind11_source_dir)
    # Not resolved: the same path the pybind11 target uses for its include dir
    get_filename_component(_pybind11_include_dir "${pybind11_source_dir}/include" ABSOLUTE)
    if(NOT EXISTS "${_pybind11_include_dir}/pybind11/pybind11.h")
        message(FATAL_ERROR "pyslam_use_bundled_pybind11: no pybind11 headers in ${_pybind11_include_dir}")
    endif()
    if(TARGET pybind11_headers)
        set_property(TARGET pybind11_headers PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "")
    endif()
    include_directories(BEFORE "${_pybind11_include_dir}")
    message(STATUS "pySLAM: using the bundled pybind11 headers in ${_pybind11_include_dir}")
endfunction()
