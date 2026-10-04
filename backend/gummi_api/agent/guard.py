"""Self-check before sending (D-57): fast code checks on the agent's draft. Any problem triggers one rewrite.

These encode the rules that matter most for safety and trust, so they run on every answer, not only in evaluation.
"""
import re

HEDGE = re.compile(r"likely|about|around|roughly|~|≈|estimate|could|would|might|probably|expect|forecast|near", re.I)
PAST = re.compile(r"reading|was|were|ago|peaked|spiked|predicted|rose|hit|reached|went|earlier|this morning|yesterday", re.I)
GLUCOSE = re.compile(r"(\d{2,3}(?:\.\d)?)\s*(?:mg/?dl)", re.I)
NUM = re.compile(r"(?<![\w.])(\d{2,3}(?:\.\d)?)(?![\w.])")
DOSE = re.compile(r"\b\d+\s*(units?|u)\b|\b\d+\s*mg\b(?!\s*/\s*dl)|(increase|decrease|double|skip|stop|change) (your )?"
                  r"(dose|insulin|metformin|medication|meds)", re.I)
SYMPTOM = re.compile(r"shak|sweat|dizz|faint|confus|light-?headed|palpitat|racing heart|blurry|unwell|pass(ing)? out", re.I)
EXERCISE = re.compile(r"\bwalk|exercise|stroll|jog|run\b", re.I)
CHECK = re.compile(r"check|fingerstick|finger stick|dexcom app", re.I)
LINES = {70.0, 140.0, 10.0, 15.0, 20.0, 30.0, 60.0}


CLAIMS_LOG = re.compile(r"\b(logged|added|saved|put)\b[^.]{0,40}\b(log|it|that|them|for you)\b|\bin your (food )?log\b", re.I)


def problems(user_msg: str, answer: str, tool_numbers: set[float], high: float, low: float, logged: bool = True,
             verdict: str | None = None) -> list[str]:
    out = []
    first = answer.strip().lower()[:30]
    if verdict == "wait" and (first.startswith("yes") or first.startswith("go ")):
        out.append("simulate_food's verdict is wait, but the reply opens with yes; open with \"I'd wait:\"")
    if verdict in ("go", "go_with_tweak") and re.match(r"(no\b|i'?d wait|wait\b|not yet)", first):
        out.append(f"simulate_food's verdict is {verdict}, but the reply says to wait; open with \"Yes\"")
    if not logged and CLAIMS_LOG.search(answer):
        out.append("says food was logged, but nothing was logged this turn; don't claim it, offer to add it instead")
    if DOSE.search(answer):
        out.append("mentions a medication or insulin dose; never give dosing advice")
    if SYMPTOM.search(user_msg):
        if EXERCISE.search(answer):
            out.append("suggested a walk or exercise to someone reporting symptoms")
        if not CHECK.search(answer):
            out.append("someone reported symptoms; tell them to check their glucose now with their Dexcom app or a fingerstick")
    lines = {high, low} | LINES
    for m in GLUCOSE.finditer(answer):
        n = float(m.group(1))
        if n in lines:
            continue
        before = answer[max(0, m.start() - 45):m.start()]
        if not HEDGE.search(before) and not PAST.search(before):
            out.append(f"'{m.group(0)}' is stated as fact; say 'likely' or 'about' for any glucose now or later")
            break
    said = {float(x) for x in NUM.findall(answer)} - lines
    stray = sorted(n for n in said if n >= 40 and not any(abs(n - t) <= 1.0 for t in tool_numbers))
    if stray:
        out.append(f"numbers {stray} are not in any tool result; use only numbers the tools returned")
    for sentence in re.split(r"(?<=[.!?])\s+", answer):
        if (re.search(r"(snack|protein|food|eat)[^.]{0,60}(lower|bring (it|you|that|things) down|reduce|drop)", sentence, re.I)
                and not re.search(r"walk|half|smaller|portion|skip", sentence, re.I)):
            out.append("suggested eating to lower glucose; only walks lower a peak")
            break
    return out


def numbers_in(obj) -> set[float]:
    return {float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", str(obj))}
