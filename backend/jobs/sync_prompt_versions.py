"""Databricks Job (file-arrival trigger on agent_memory/lessons_history/): when the Reviewer agent learns a lesson,
register a new version of the Coach prompt in the Unity Catalog prompt registry and move the production alias.

Runs on serverless as the prompt's owner, so the App needs no rights on the prompt itself (D-81).
"""
import json
import sys

import mlflow

sys.path.insert(0, "/Workspace/Users/somalrajupc@gmail.com/gummi-backend")
from gummi_api.agent.prompts import RULES, SOUL  # noqa: E402

NAME = "workspace.gummi_agent.gummi_coach_prompt"
LESSONS = "/Volumes/workspace/gummi_data/landing/agent_memory/lessons.json"

mlflow.set_tracking_uri("databricks")
mlflow.set_registry_uri("databricks-uc")
lessons = [x["lesson"] for x in json.load(open(LESSONS))]
prod = mlflow.genai.load_prompt(f"prompts:/{NAME}@production")
new = [x for x in lessons if x not in prod.template]
if not new:
    print(f"production v{prod.version} already has all {len(lessons)} lessons")
else:
    block = "Lessons from reviewing past conversations:\n" + "\n".join(f"- {x}" for x in lessons)
    p = mlflow.genai.register_prompt(name=NAME, template=f"{SOUL}\n\n{RULES}\n\n{block}\n\nContext: {{{{context}}}}",
                                     commit_message=("Reviewer lesson: " + " | ".join(new))[:500],
                                     tags={"agent": "coach", "lessons": str(len(lessons))})
    mlflow.genai.set_prompt_alias(NAME, alias="production", version=p.version)
    print(f"registered v{p.version} with {len(new)} new lesson(s); production -> v{p.version}")
