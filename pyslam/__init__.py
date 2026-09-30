import os
import sys

if sys.platform == "darwin":
    # Some models use ops that Apple MPS does not implement (e.g. torchvision's deform_conv2d in ALIKED):
    # let torch run just those ops on the CPU. This must be set before torch is imported.
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
