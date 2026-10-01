import os
import sys

# OpenMP: idle worker threads must not spin. conda-forge torch uses LLVM's OpenMP runtime (with MKL on
# Linux), whose threads busy-wait for 200 ms after each parallel region and starve pySLAM's own threads:
# on Linux, tracking went from 0.018 to 0.277 s per frame (track lost). KMP_BLOCKTIME is read only by
# LLVM's runtime; GNU OpenMP (pip torch on Linux) ignores it, and is slower with OMP_WAIT_POLICY=passive.
# The OpenMP runtime reads it once, when torch/numpy are first imported, so the main_*.py scripts
# import pyslam first. A value set in the environment takes precedence.
os.environ.setdefault("KMP_BLOCKTIME", "0")

if sys.platform == "darwin":
    # Some models use ops that Apple MPS does not implement (e.g. torchvision's deform_conv2d in ALIKED):
    # let torch run just those ops on the CPU. This must be set before torch is imported.
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
