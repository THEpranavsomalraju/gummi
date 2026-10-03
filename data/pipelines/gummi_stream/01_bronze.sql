-- gummi_stream, bronze layer (Lakeflow Declarative Pipeline, serverless).
-- Source: StreamEvent JSON lines (CONTRACT.md section 3) written by the Databricks App every 5 seconds to
--   /Volumes/<CATALOG>/gummi_data/landing/events/<YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl
-- ${landing_path} is a pipeline configuration value set in data/resources/gummi_stream.pipeline.yml.
-- Same pattern as the workshop's earthquake pipeline: read_files as text, parse to VARIANT, keep lineage.

CREATE OR REFRESH STREAMING TABLE stream_bronze_events (
  CONSTRAINT parsed_json EXPECT (event IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT has_event_id EXPECT (event_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT known_kind EXPECT (kind IN ('cgm', 'meal', 'steps', 'walk', 'prediction', 'grade', 'card', 'chat'))
)
COMMENT 'Every StreamEvent line from the landing volume, parsed to VARIANT, with lineage. One row per event. landed_at = file write time, ingested_at = pipeline processing time; their difference is the pipeline lag.'
AS SELECT
  event_id,
  source,
  user_id,
  kind,
  t,
  released_at,
  payload,
  source_file,
  landed_at,
  ingested_at,
  event
FROM (
  SELECT
    parsed AS event,
    parsed:event_id::STRING AS event_id,
    parsed:source::STRING AS source,
    parsed:user_id::STRING AS user_id,
    parsed:kind::STRING AS kind,
    try_cast(parsed:t::STRING AS TIMESTAMP) AS t,
    try_cast(parsed:released_at::STRING AS TIMESTAMP) AS released_at,
    parsed:payload AS payload,
    source_file,
    landed_at,
    ingested_at
  FROM (
    SELECT
      try_parse_json(value) AS parsed,
      _metadata.file_path AS source_file,
      _metadata.file_modification_time AS landed_at,
      current_timestamp() AS ingested_at
    FROM STREAM read_files('${landing_path}', format => 'text')
  )
);
