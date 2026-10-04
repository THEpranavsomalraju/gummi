# Databricks notebook source
# MAGIC %md
# MAGIC # Gummi: start here
# MAGIC **A glucose coach that predicts, acts, and checks its own work.** For adults with prediabetes or type 2 diabetes who don't take insulin.
# MAGIC
# MAGIC Dexcom shares readings with apps about an hour late. Gummi estimates the missing hour with its own trained model, coaches from that estimate (can I eat this, should I walk), and grades every prediction against what actually happened, next to two baselines.
# MAGIC
# MAGIC No one on the team wears a Dexcom: 15 real participants from the BIG IDEAs study stream through Databricks as a live replay, and an iPhone adds real steps and walks.
# MAGIC
# MAGIC | | Open |
# MAGIC |---|---|
# MAGIC | 1. The whole system, live | [System map](https://gummi-7474657192035402.aws.databricksapps.com/api/v1/map) |
# MAGIC | 2. All 15 participants streaming | [Fleet view](https://gummi-7474657192035402.aws.databricksapps.com/api/v1/fleet/view) |
# MAGIC | 3. The Databricks App behind the phone | [App gummi](https://dbc-0f92eb43-532a.cloud.databricks.com/apps/gummi) |
# MAGIC | 4. Streaming pipeline (Lakeflow, continuous) | [gummi_stream](https://dbc-0f92eb43-532a.cloud.databricks.com/pipelines/b11d910a-48c4-4396-922c-0c249303f33f) |
# MAGIC | 5. Live accuracy dashboard (AI/BI) | [Gummi live accuracy](https://dbc-0f92eb43-532a.cloud.databricks.com/dashboardsv3/01f1bf883268170693784c519c8eb10b/published) |
# MAGIC | 6. Gummi's model in Unity Catalog | [workspace.gummi_ml.gummi_model](https://dbc-0f92eb43-532a.cloud.databricks.com/explore/data/models/workspace/gummi_ml/gummi_model) |
# MAGIC | 7. Agent traces and the agent's safety evaluation (MLflow) | [Experiment gummi-agent](https://dbc-0f92eb43-532a.cloud.databricks.com/ml/experiments/3505481683626519) |
# MAGIC | 8. Agent Bricks supervisor | [Gummi Insights](https://dbc-0f92eb43-532a.cloud.databricks.com/ml/endpoints/mas-becc8b0e-endpoint) |
# MAGIC | 9. Ask the data in plain English | [Genie: Gummi Data](https://dbc-0f92eb43-532a.cloud.databricks.com/genie/rooms/01f1bf87ea5918298b59e25b38538d16) |
# MAGIC | 10. Gummi's prompt, versioned as it learns | [workspace.gummi_ml.gummi_coach_prompt](https://dbc-0f92eb43-532a.cloud.databricks.com/explore/data/workspace/gummi_ml) (Unity Catalog prompt registry) |
# MAGIC | 11. Real Dexcom connection (sandbox, OAuth) | [Connect page](https://gummi-7474657192035402.aws.databricksapps.com/api/v1/dexcom/connect) |

# COMMAND ----------

# MAGIC %md
# MAGIC ## How the pieces fit
# MAGIC 1. **Replay and phone events** enter the **Databricks App** (FastAPI). It keeps hot state in memory so the phone gets answers in about 30 ms.
# MAGIC 2. **Gummi's own model** (ridge regression per 5-minute horizon on CGM history plus meal absorption curves) runs inside the App. Each study participant is predicted by one of **5 fold models that never saw them**.
# MAGIC 3. **Every prediction is graded** two hours later against what happened, next to the published **CGM-only** method and a **last-value** guess.
# MAGIC 4. **Agents act on events**: Coach (chat), Meal Story, Walk Coach, Morning Briefing and Evening Recap. They call tools that run the model; the LLM never makes up a number. Every run is an **MLflow trace**.
# MAGIC 5. **Every event lands in a Unity Catalog volume**. The **Lakeflow** pipeline turns it into bronze, silver and gold streaming tables within seconds. The gold tables feed the fleet view, the Evening Recap agent and **Gummi Insights**, an Agent Bricks supervisor over Genie, Unity Catalog functions and a Knowledge Assistant.

# COMMAND ----------

# MAGIC %md
# MAGIC ## How Gummi checks and improves itself
# MAGIC 1. **Before sending**, every answer passes code checks (no dosing, estimates hedged, every number from a tool, no walk advice after symptoms). A failing draft is rewritten once.
# MAGIC 2. **After sending**, a separate **Reviewer agent** (Llama 4 Maverick, a different model family) scores the reply and attaches the scores to its **MLflow trace** as feedback.
# MAGIC 3. **When the Reviewer finds a mistake**, it writes one general lesson. Lessons go into Gummi's prompt for future conversations, and each one is registered as a new version of `workspace.gummi_ml.gummi_coach_prompt` in the **Unity Catalog prompt registry**. A filter blocks any lesson that touches medication or loosens a rule.
# MAGIC 4. **MLflow production monitoring** runs safety, treatment-advice, symptom-handling and estimate-wording judges on live traces automatically (experiment *gummi-agent* → Monitoring).
# MAGIC 5. **The model learns too**: every graded meal updates that person's personal carb factor and offset.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Live: events streaming in right now

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT kind, count(*) AS events, max(released_at) AS newest
# MAGIC FROM workspace.gummi_data.stream_bronze_events
# MAGIC GROUP BY kind ORDER BY events DESC

# COMMAND ----------

# MAGIC %md
# MAGIC ## Live: is Gummi beating the baselines? (out-of-sample, from the gold table)
# MAGIC Mean absolute error in mg/dL; lower is better. Windows where a phone walk overlapped replayed glucose are left out.

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT window_type, grades, gummi_mae_mg_dl AS gummi, cgm_only_mae_mg_dl AS cgm_only, last_value_mae_mg_dl AS last_value,
# MAGIC        gummi_beats_cgm_only_pct, gummi_beats_last_value_pct
# MAGIC FROM workspace.gummi_data.stream_gold_accuracy
# MAGIC WHERE sample = 'out-of-sample' AND user_id = 'ALL'
# MAGIC ORDER BY window_type

# COMMAND ----------

# MAGIC %md
# MAGIC ## Offline evaluation: participant-grouped cross-validation (DRAFT until the team approves)
# MAGIC Five folds grouped by participant, so no one is in both training and test. The published CGM-only baseline is reproduced at 13.90 RMSE at 30 minutes.

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT window, horizon_min,
# MAGIC   round(max(CASE WHEN model = 'gummi_cgm_meals' THEN mae_mean END), 1) AS gummi,
# MAGIC   round(max(CASE WHEN model = 'cgm_only' THEN mae_mean END), 1) AS cgm_only,
# MAGIC   round(max(CASE WHEN model = 'persistence' THEN mae_mean END), 1) AS last_value
# MAGIC FROM workspace.gummi_ml.eval_results
# MAGIC WHERE horizon_min IN (30, 60, 90, 120)
# MAGIC GROUP BY window, horizon_min ORDER BY window, horizon_min

# COMMAND ----------

# MAGIC %md
# MAGIC ## Try the agent behind Gummi Insights
# MAGIC Ask about one participant's own history. It picks its sub-agent (Genie, a Unity Catalog function, or the reports) and answers with the baselines next to every accuracy number.

# COMMAND ----------

from databricks.sdk import WorkspaceClient

question = "For participant p_012: which meals raised their glucose the most, and how did Gummi's predictions compare with CGM-only and last value?"
resp = WorkspaceClient().api_client.do("POST", "/serving-endpoints/mas-becc8b0e-endpoint/invocations",
                                       body={"input": [{"role": "user", "content": question}]})
for item in resp.get("output", []):
    if item.get("type") == "function_call":
        print("tool chosen:", item.get("name"))
    if item.get("type") == "message":
        for c in item.get("content", []):
            if c.get("type") == "output_text":
                print("\n" + c["text"])
