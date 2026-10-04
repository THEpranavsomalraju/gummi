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


def item(name: str, quantity: float = 1, unit: str | None = None, **given) -> dict:
    """One Meal item. Macros given by the caller (edits, dataset rows) win over the seed table."""
    per, source = lookup(name)
    out = {"name": name, "quantity": float(quantity), "unit": unit or per["unit"]}
    for k in MACROS:
        out[k] = round(float(given[k]) if given.get(k) is not None else per[k] * float(quantity), 1)
    out["nutrition_source"] = given.get("nutrition_source") or ("dataset" if any(k in given for k in MACROS) else source)
    out["editable"] = True
    return out


def totals(items: list[dict]) -> dict:
    return {k: round(sum(i[k] for i in items), 1) for k in MACROS}
