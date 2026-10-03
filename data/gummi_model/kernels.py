"""Meal absorption kernels: Gamma(shape=3, mode=peak). Closed form, numpy only."""
from __future__ import annotations

import numpy as np

from .config import KERNEL_SHAPE

assert KERNEL_SHAPE == 3, "closed-form CDF below assumes integer shape 3"


def cdf(minutes, peak: float) -> np.ndarray:
    """Fraction absorbed `minutes` after eating. 0 before eating."""
    theta = peak / (KERNEL_SHAPE - 1.0)
    x = np.clip(np.asarray(minutes, dtype=float), 0.0, None) / theta
    return 1.0 - np.exp(-x) * (1.0 + x + 0.5 * x * x)


def rate(minutes, peak: float) -> np.ndarray:
    """Absorption rate scaled so the peak equals 1. 0 before eating."""
    m = np.asarray(minutes, dtype=float)
    theta = peak / (KERNEL_SHAPE - 1.0)
    safe = np.clip(m, 1e-9, None)
    out = (safe / peak) ** 2 * np.exp(-(safe - peak) / theta)
    return np.where(m > 0, out, 0.0)
