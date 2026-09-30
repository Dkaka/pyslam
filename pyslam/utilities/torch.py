"""
* This file is part of PYSLAM
* Adpated from adapted from https://github.com/lzx551402/contextdesc/blob/master/utils/tf.py, see the license therein.
* Copyright (C) 2016-present Luigi Freda <luigi dot freda at gmail dot com>
*
* PYSLAM is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* PYSLAM is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with PYSLAM. If not, see <http://www.gnu.org/licenses/>.
"""

import os
import torch
import numpy as np


# Convert to numpy
def get_torch_device(prefer_gpu: bool = True) -> torch.device:
    """
    Return the best available torch device: CUDA, then Apple MPS, then CPU.
    Set the environment variable PYSLAM_TORCH_DEVICE (e.g. "cpu", "mps", "cuda") to force one.
    """
    forced = os.environ.get("PYSLAM_TORCH_DEVICE")
    if forced:
        return torch.device(forced)
    if prefer_gpu and torch.cuda.is_available():
        return torch.device("cuda")
    if prefer_gpu and torch.backends.mps.is_available() and torch.backends.mps.is_built():
        return torch.device("mps")
    return torch.device("cpu")


def trust_torch_hub_repos(repos):
    """
    Add GitHub repos ("owner/name") to torch.hub's trusted list, as answering 'y' to its prompt does.
    torch >= 2.13 asks for confirmation before loading an untrusted repo; in a child process with no
    terminal that prompt cannot be answered, so pyslam pre-trusts the repos of the models the user chose.
    """
    hub_dir = torch.hub.get_dir()
    os.makedirs(hub_dir, exist_ok=True)
    filepath = os.path.join(hub_dir, "trusted_list")
    trusted = set()
    if os.path.exists(filepath):
        with open(filepath) as f:
            trusted = {line.strip() for line in f}
    missing = [r.replace("/", "_") for r in repos if r.replace("/", "_") not in trusted]
    if missing:
        with open(filepath, "a") as f:
            f.writelines(name + "\n" for name in missing)


def to_np(x, ret_type=float) -> np.ndarray:
    x_np: np.ndarray = None
    if type(x) == torch.Tensor:
        x_np = x.detach().cpu().numpy()
    else:
        x_np = np.array(x)
    x_np = x_np.astype(ret_type)
    return x_np


def to_device(batch, device, callback=None, non_blocking=False):
    """Transfer some variables to another device (i.e. GPU, CPU:torch, CPU:numpy).

    batch: list, tuple, dict of tensors or other things
    device: pytorch device or 'numpy'
    callback: function that would be called on every sub-elements.
    """
    if callback:
        batch = callback(batch)

    if isinstance(batch, dict):
        return {k: to_device(v, device) for k, v in batch.items()}

    if isinstance(batch, (tuple, list)):
        return type(batch)(to_device(x, device) for x in batch)

    x = batch
    if device == "numpy":
        if isinstance(x, torch.Tensor):
            x = x.detach().cpu().numpy()
    elif x is not None:
        if isinstance(x, np.ndarray):
            x = torch.from_numpy(x)
        if torch.is_tensor(x):
            x = x.to(device, non_blocking=non_blocking)
    return x


def to_numpy(x):
    return to_device(x, "numpy")


def to_cpu(x):
    return to_device(x, "cpu")


def to_cuda(x):
    return to_device(x, "cuda")


def safe_empty_cache() -> None:
    """Aggressively free CUDA/CPU memory."""
    import gc

    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        torch.cuda.ipc_collect()


def invert_se3(T: torch.Tensor) -> torch.Tensor:
    """Invert batched SE3 matrices."""
    R = T[..., :3, :3]
    t = T[..., :3, 3]
    Rt = R.transpose(-1, -2)
    t_inv = -(Rt @ t.unsqueeze(-1)).squeeze(-1)
    Tin = torch.eye(4, device=T.device, dtype=T.dtype).expand(T.shape)
    Tin = Tin.clone()
    Tin[..., :3, :3] = Rt
    Tin[..., :3, 3] = t_inv
    return Tin
