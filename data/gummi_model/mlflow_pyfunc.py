"""MLflow pyfunc wrapper so gummi_model is registered in Unity Catalog (the App still imports gummi_model directly).

Only the registration notebook imports this module; gummi_model itself never needs mlflow.
Input: a DataFrame with one column "request", each a JSON string:
  {"method": "estimate_gap" | "forecast" | "cgm_only_forecast" | "gummi_view" | "simulate",
   "user_id": "p_012" (replay participants get the fold model that never saw them, D-26),
   "now": ISO time, "minutes": 120, "profile": {...}, "personal": {...},
   "cgm": [{"t": ..., "glucose_mg_dl": ...}], "meals": [{"eaten_at": ..., "carbs_g": ...}],
   "items_macros": {...} (simulate only)}
Output: one JSON string per request.
"""
from __future__ import annotations

import json

import mlflow.pyfunc
import pandas as pd


class GummiPyfunc(mlflow.pyfunc.PythonModel):
    def load_context(self, context):
        from gummi_model import GlucoseModel
        self.model = GlucoseModel.load(context.artifacts["gummi_model"])

    def predict(self, context, model_input: pd.DataFrame, params=None):
        from gummi_model import UserContext
        out = []
        for raw in model_input["request"]:
            r = json.loads(raw)
            cgm = pd.DataFrame(r.get("cgm") or [])
            meals = pd.DataFrame(r.get("meals") or [])
            user = r.get("user_id", "anonymous")
            ctx = UserContext(user, r.get("profile") or {}, cgm, meals if len(meals) else None, None, r.get("personal"))
            m = self.model.for_user(user)
            now, method = r["now"], r.get("method", "forecast")
            if method == "estimate_gap":
                res = m.estimate_gap(ctx, now)
            elif method == "gummi_view":
                res = m.gummi_view(ctx, now)
            elif method == "simulate":
                res = m.simulate(ctx, now, r["items_macros"], r.get("eat_at"))
            elif method == "cgm_only_forecast":
                res = m.cgm_only_forecast(ctx, now, int(r.get("minutes", 120)))
            else:
                res = m.forecast(ctx, now, int(r.get("minutes", 120)))
            out.append(json.dumps(res))
        return pd.Series(out)
