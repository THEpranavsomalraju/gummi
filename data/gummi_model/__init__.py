"""Gummi's glucose model (CONTRACT.md section 8). Inference needs only numpy + pandas + saved coefficients."""
from .config import VERSION as __version__
from .model import GlucoseModel, UserContext
from .walk import permutation_test

__all__ = ["GlucoseModel", "UserContext", "permutation_test", "__version__"]
