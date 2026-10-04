"""Pydantic mirrors of CONTRACT.md section 3 (v1.2). Routes return plain dicts; tests validate them against these."""
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class GlucosePoint(Strict):
    t: str
    glucose_mg_dl: float
    kind: Literal["confirmed", "estimate", "forecast"]


class BandPoint(Strict):
    t: str
    glucose_mg_dl: float
    band_low_mg_dl: float
    band_high_mg_dl: float
    kind: Literal["estimate", "forecast"]


class GummiView(Strict):
    glucose_mg_dl: float
    band_low_mg_dl: float
    band_high_mg_dl: float
    trend: Literal["rising_fast", "rising", "flat", "falling", "falling_fast"]
    as_of: str
    minutes_since_confirmed: int
    confidence: Literal["high", "medium", "low"]


class Prediction(Strict):
    prediction_id: str
    kind: Literal["meal", "nowcast"]
    made_at: str
    about: str
    meal_id: Optional[str] = None
    window_start: str
    window_end: str
    predicted_peak_mg_dl: float
    predicted_curve: list[BandPoint]
    cgm_only_peak_mg_dl: Optional[float]
    last_value_peak_mg_dl: float
    status: Literal["pending", "graded"]


class Grade(Strict):
    grade_id: str
    prediction_id: str
    kind: Literal["meal", "nowcast"]
    graded_at: str
    points: int
    gummi_mae_mg_dl: float
    cgm_only_mae_mg_dl: Optional[float]
    last_value_mae_mg_dl: float
    gummi_peak_error_mg_dl: float
    within_band_pct: float
    walk_effect_graded: bool
    gummi_beats_cgm_only: Optional[bool]
    gummi_beats_last_value: bool
    message: str


class CardAction(Strict):
    label: str
    kind: Literal["open_chat", "log_due_meal"]
    prompt: Optional[str] = None
    due_id: Optional[str] = None


Mood = Literal["calm", "rising", "high", "dipping", "low", "proud", "happy", "sleepy", "thinking"]


class StoryCard(Strict):
    card_id: str
    type: Literal["morning_briefing", "meal_due", "meal_logged", "prediction", "meal_story", "grade",
                  "walk_suggested", "walk_summary", "evening_recap", "dexcom_status"]
    created_at: str
    title: str
    body: str
    mood: Mood
    attachments: Optional[dict] = None
    actions: list[CardAction]
    trace_id: Optional[str] = None
    generated_by: Literal["agent", "template"]


class AlertAction(Strict):
    label: str
    kind: Literal["start_walk", "open_chat", "dismiss"]
    minutes: Optional[int] = None


class Alert(Strict):
    alert_id: str
    type: Literal["walk_suggested", "high_forecast", "low_forecast", "dexcom_gap"]
    message: str
    created_at: str
    expires_at: str
    action: AlertAction


class DexcomStatus(Strict):
    connected: bool
    environment: Literal["sandbox", "production"]
    data_through: Optional[str]
    delay_minutes: int
    last_sync: Optional[str]
    last_error: Optional[str]
    source: Literal["dexcom_api", "replay", "none"]
    ingest_mode: Literal["status_only", "time_shifted"]


class Today(Strict):
    time_in_range_pct: float
    peak_mg_dl: float
    meals: int
    steps: int
    walks: int
    gummi_mae_mg_dl: Optional[float]
    cgm_only_mae_mg_dl: Optional[float]
    last_value_mae_mg_dl: Optional[float]


class ProfileLines(Strict):
    high_line_mg_dl: float
    low_line_mg_dl: float


class UpcomingDue(Strict):
    due_id: str
    due_at: str
    title: str
    body: str


class State(Strict):
    user_id: str
    following: Optional[str]
    acting_as: Optional[str]
    dexcom: DexcomStatus
    gummi_view: Optional[GummiView]
    confirmed: list[GlucosePoint]
    estimate: list[BandPoint]
    forecast: list[BandPoint]
    mood: Mood
    alert: Optional[Alert]
    top_card: Optional[StoryCard]
    pending_predictions: list[Prediction]
    today: Today
    profile: ProfileLines
    upcoming_due: list[UpcomingDue]
    replay_now: Optional[str]
    stream: "StreamStatus"
    model_version: str
    server_time: str


class MealItem(Strict):
    name: str
    quantity: float
    unit: str
    carbs_g: float
    sugar_g: float
    fiber_g: float
    protein_g: float
    fat_g: float
    calories: float
    nutrition_source: Literal["seed", "llm_estimate", "dataset"]
    editable: bool


class MealTotals(Strict):
    carbs_g: float
    sugar_g: float
    fiber_g: float
    protein_g: float
    fat_g: float
    calories: float


class Meal(Strict):
    meal_id: str
    eaten_at: str
    source: Literal["chat", "manual", "replay", "replay_due", "replay_auto"]
    items: list[MealItem]
    totals: MealTotals
    is_standard_breakfast: bool
    prediction_id: Optional[str]


class Alternative(Strict):
    label: str
    peak_mg_dl: float
    effect_source: Optional[Literal["literature", "your data"]] = None


class Simulation(Strict):
    items: list[MealItem]
    eat_at: str
    baseline_curve: list[BandPoint]
    with_food_curve: list[BandPoint]
    peak_mg_dl: float
    peak_at: str
    verdict: Literal["go", "go_with_tweak", "wait"]
    summary: str
    alternatives: list[Alternative]
    method: Literal["model", "breakfast_response"]
    prediction_id: str


class WalkSummary(Strict):
    started_at: str
    ended_at: str
    minutes: int
    steps: int
    cadence_spm: int
    intensity: Literal["sedentary", "light", "moderate", "vigorous"]
    forecast_peak_drop_mg_dl: float
    effect_source: Literal["literature", "your data"]


class StreamEvent(Strict):
    event_id: str
    source: Literal["replay", "dexcom_sandbox", "iphone", "app"]
    user_id: str
    kind: Literal["cgm", "meal", "steps", "walk", "prediction", "grade", "card", "chat"]
    t: str
    released_at: str
    payload: dict


class ReplayAnchor(Strict):
    replay_time: Optional[str]
    wall_time: Optional[str]


class StreamStatus(Strict):
    running: bool
    paused: bool
    speed: float
    delay_minutes: int
    participants: int
    replay_clock: Optional[str]
    replay_anchor: ReplayAnchor
    events_released: int
    events_per_second: float
    pipeline_lag_seconds: Optional[float]


class FleetEntry(Strict):
    user_id: str
    display_name: str
    mood: Mood
    data_through: Optional[str]
    sparkline: list[GlucosePoint]
    grades: int
    gummi_mae_mg_dl: Optional[float]
    cgm_only_mae_mg_dl: Optional[float]
    last_value_mae_mg_dl: Optional[float]
    last_grade: Optional[Grade]


class Fleet(Strict):
    entries: list[FleetEntry]
    fleet_gummi_mae_mg_dl: Optional[float]
    fleet_cgm_only_mae_mg_dl: Optional[float]
    fleet_last_value_mae_mg_dl: Optional[float]
    stream: StreamStatus


class Profile(Strict):
    user_id: str
    display_name: str
    high_line_mg_dl: float
    low_line_mg_dl: float
    timezone: str
    onboarded: bool


class Health(Strict):
    status: str
    mode: Literal["mock", "live"]
    version: str


State.model_rebuild()
