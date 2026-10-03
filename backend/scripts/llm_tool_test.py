"""D-04 spike: does each chat endpoint return a proper tool call, and how fast? Uses the CLI profile via the SDK."""
import json, sys, time
from databricks.sdk import WorkspaceClient

w = WorkspaceClient(profile="gummi")
TOOLS = [{"type": "function", "function": {
    "name": "log_meal", "description": "Save a meal the user ate and create a glucose prediction.",
    "parameters": {"type": "object", "properties": {
        "items": {"type": "array", "items": {"type": "object", "properties": {
            "name": {"type": "string"}, "quantity": {"type": "number"}, "unit": {"type": "string"}},
            "required": ["name", "quantity", "unit"]}},
        "eaten_at": {"type": "string", "description": "ISO 8601 time, or null for now"}},
        "required": ["items"]}}}]
MSGS = [{"role": "system", "content": "You are Gummi, a glucose coach. Past or present eating gets logged with log_meal."},
        {"role": "user", "content": "I just had two waffles and a black coffee"}]

for ep in sys.argv[1:]:
    t0 = time.time()
    try:
        r = w.api_client.do("POST", "/serving-endpoints/chat/completions",
                            body={"model": ep, "messages": MSGS, "tools": TOOLS, "max_tokens": 400})
        msg = r["choices"][0]["message"]
        calls = [(c["function"]["name"], json.loads(c["function"]["arguments"])) for c in msg.get("tool_calls") or []]
        print(f"{ep:45s} {time.time()-t0:5.2f}s tool_calls={calls}")
    except Exception as e:
        print(f"{ep:45s} {time.time()-t0:5.2f}s ERROR {str(e)[:150]}")
