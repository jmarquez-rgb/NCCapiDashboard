-- ai_flags.sql
-- Remote Scouts QA flagging: one JSON payload of scored calls for flagged.html
-- Tenant: thrio-prod-4258998.4258998  (last 30 days)
--
-- Needs: the post-call QA step must save its JSON answer in the workitem
-- variable  rsQaJson  (see rs_qa_prompt.txt).
-- Calls without rsQaJson are left out.
--
-- Not yet run against the tenant. If a column name differs, fix it here.

WITH users_latest AS (
  SELECT
    workitemId,
    userName
  FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS_USERS`
  WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY workitemId
    ORDER BY CAST(createdAt AS INT64) DESC
  ) = 1
),

raw AS (
  SELECT
    d.id AS call_id,
    d._PARTITIONDATE AS call_date,
    COALESCE(
      NULLIF(u.userName, ''),
      JSON_VALUE(r.object, '$.agentUsername')
    ) AS agent,
    -- QA answer saved as text: remove code fences, then parse
    SAFE.PARSE_JSON(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          TRIM(JSON_VALUE(r.object, '$.data.rsQaJson')),
          r'^```(?:json)?\s*',
          ''
        ),
        r'\s*```$',
        ''
      )
    ) AS qa_from_text,
    -- QA answer saved as an object
    JSON_QUERY(r.object, '$.data.rsQaJson') AS qa_from_object,
    IF(
      STARTS_WITH(JSON_VALUE(r.object, '$.data.aiContactSentiment'), 'workitem.'),
      NULL,
      JSON_VALUE(r.object, '$.data.aiContactSentiment')
    ) AS ai_contact_sentiment,
    IF(
      STARTS_WITH(JSON_VALUE(r.object, '$.data.aiAgentSentiment'), 'workitem.'),
      NULL,
      JSON_VALUE(r.object, '$.data.aiAgentSentiment')
    ) AS ai_agent_sentiment
  FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
  JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
    ON r.callId = d.id
  LEFT JOIN users_latest AS u
    ON u.workitemId = d.id
  WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
),

base AS (
  SELECT
    call_id,
    call_date,
    agent,
    ai_contact_sentiment,
    ai_agent_sentiment,
    IF(
      JSON_TYPE(qa_from_text) = 'object',
      qa_from_text,
      IF(JSON_TYPE(qa_from_object) = 'object', qa_from_object, NULL)
    ) AS qa
  FROM raw
)

SELECT
  TO_JSON_STRING(
    ARRAY_AGG(
      STRUCT(
        call_id,
        CAST(call_date AS STRING) AS call_date,
        agent,
        SAFE_CAST(JSON_VALUE(qa, '$.weighted_score') AS FLOAT64) AS weighted_score,
        JSON_VALUE(qa, '$.grade') AS grade,
        JSON_VALUE(qa, '$.interaction_type') AS interaction_type,
        JSON_QUERY(qa, '$.pillars') AS pillars,
        JSON_QUERY(qa, '$.sentiment') AS sentiment,
        JSON_QUERY(qa, '$.talk_time') AS talk_time,
        JSON_QUERY(qa, '$.script') AS script,
        JSON_QUERY(qa, '$.objections') AS objections,
        SAFE_CAST(JSON_VALUE(qa, '$.caller_repeat_requests') AS INT64) AS caller_repeat_requests,
        JSON_QUERY(qa, '$.flags') AS flags,
        SAFE_CAST(JSON_VALUE(qa, '$.flagged') AS BOOL) AS flagged,
        JSON_VALUE(qa, '$.flag_reason_summary') AS flag_reason_summary,
        JSON_QUERY(qa, '$.coaching') AS coaching,
        SAFE_CAST(JSON_VALUE(qa, '$.phi_detected') AS BOOL) AS phi_detected,
        JSON_VALUE(qa, '$.summary') AS summary,
        ai_contact_sentiment AS aiContactSentiment,
        ai_agent_sentiment AS aiAgentSentiment
      )
      ORDER BY call_date DESC
    )
  ) AS payload
FROM base
WHERE qa IS NOT NULL;
