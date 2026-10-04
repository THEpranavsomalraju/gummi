"""Nutrition: seed foods first, then an estimate (Phase 1: a generic estimate; Phase 2: LLM structured JSON)."""
import json
from pathlib import Path

SEED = json.loads((Path(__file__).parent / "seed_foods.json").read_text())
MACROS = ("carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g", "calories")
GENERIC = {"unit": "serving", "carbs_g": 30.0, "sugar_g": 8.0, "fiber_g": 2.0, "protein_g": 8.0, "fat_g": 8.0, "calories": 230}


def lookup(name: str) -> tuple[dict, str]:
    key = name.strip().lower().rstrip("s")
    for food, per in SEED.items():
        if food == key or food.rstrip("s") == key or food in key:
            return per, "seed"
    return GENERIC, "llm_estimate"


WEIGHT_UNITS = {"g", "gram", "grams", "gr", "oz", "ounce", "ounces", "ml", "milliliter", "milliliters", "lb", "lbs"}
MAX_PORTIONS = 6.0


def portions(quantity, unit: str | None) -> float:
    """Seed macros are per portion. A weight ("28 g", "4 oz") means one normal portion, never 28 portions, and no
    food counts as more than 6 portions: a units mistake must never turn a snack into 800 g of carbs."""
    q = float(quantity or 1)
    if (unit or "").strip().lower().rstrip(".") in WEIGHT_UNITS:
        return 1.0
    return max(0.25, min(q, MAX_PORTIONS))


def item(name: str, quantity: float = 1, unit: str | None = None, **given) -> dict:
    """One Meal item. Macros given by the caller (edits, dataset rows) win over the seed table."""
    per, source = lookup(name)
    if not any(given.get(k) is not None for k in MACROS):
        quantity = portions(quantity, unit)
    out = {"name": name, "quantity": float(quantity), "unit": unit or per["unit"]}
    for k in MACROS:
        out[k] = round(float(given[k]) if given.get(k) is not None else per[k] * float(quantity), 1)
    out["nutrition_source"] = given.get("nutrition_source") or ("dataset" if any(k in given for k in MACROS) else source)
    out["editable"] = True
    return out


def totals(items: list[dict]) -> dict:
    return {k: round(sum(i[k] for i in items), 1) for k in MACROS}
