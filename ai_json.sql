SELECT
  TO_JSON_STRING(
    STRUCT(
      FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', CURRENT_TIMESTAMP()) AS updated_at,
      (
        SELECT AS STRUCT
          COUNT(*) AS handled,
          COUNTIF(c.ended_by = 'agent') AS agent_ended,
          COUNTIF(c.ended_by = 'customer') AS customer_ended,
          COUNTIF(c.scored) AS scored,
          COUNTIF(c.scored AND c.ended_by = 'agent') AS scored_agent_ended
        FROM (
          SELECT
            CASE
              WHEN d.terminationReason IN (2, 22, 23, 24) THEN 'agent'
              WHEN d.terminationReason IN (1, 21) THEN 'customer'
              ELSE 'other'
            END AS ended_by,
            COALESCE(REGEXP_CONTAINS(JSON_VALUE(r.object, '$.data.qaRaw'), r'Hybrid Score|composite|Overall Score'), FALSE) AS scored
          FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
          JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
            ON r.callId = d.id
          WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
            AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
            AND d.channelType = 'InboundCall'
            AND d.talkTime > 0
        ) AS c
      ) AS qa_coverage,
      ARRAY(
        SELECT AS STRUCT e.*
        FROM (
          SELECT
            SUBSTR(b.id, 1, 8) AS workitem,
            b.campaignName,
            b.channelType,
            b.source,
            CASE
              WHEN b.terminationReason IN (2, 22, 23, 24) THEN 'agent'
              WHEN b.terminationReason IN (1, 21) THEN 'customer'
              ELSE 'other'
            END AS ended_by,
            b.transferred > 0 AS transferred_to_agent,
            ROUND(b.talkTime / 1000, 1) AS talk_sec,
            DATE(TIMESTAMP_MILLIS(b.createdAt), 'America/Phoenix') AS day,
            b.createdAt AS created_ms,
            IF(REGEXP_CONTAINS(b.txt, 'Hybrid Score'), 'hybrid', IF(REGEXP_CONTAINS(b.txt, 'composite'), 'long', 'short')) AS template,
            COALESCE(
              CAST(ROUND(SAFE_CAST(REGEXP_EXTRACT(b.txt, r'Hybrid Score[^<]*</strong>\s*([\d.]+)') AS FLOAT64)) AS INT64),
              SAFE_CAST(REGEXP_EXTRACT(b.txt, r'>(\d{1,3})</div>\s*<div[^>]*>composite</div>') AS INT64),
              CAST(ROUND(SAFE_CAST(REGEXP_EXTRACT(b.txt, r'Overall Score:?\s*(?:</[a-zA-Z0-9]+>)?\s*(\d+)\s*/\s*16') AS INT64) / 16 * 100) AS INT64),
              CAST(ROUND(SAFE_CAST(REGEXP_EXTRACT(b.txt, r'Overall Score:</b>\s*(\d+)') AS INT64) / 16 * 100) AS INT64)
            ) AS composite,
            COALESCE(
              SAFE_CAST(REGEXP_EXTRACT(b.txt, r'ISDC Total[^<]*</strong>\s*(\d+)') AS INT64),
              SAFE_CAST(REGEXP_EXTRACT(b.txt, r'Overall Score:?\s*(?:</[a-zA-Z0-9]+>)?\s*(\d+)\s*/\s*16') AS INT64),
              SAFE_CAST(REGEXP_EXTRACT(b.txt, r'Overall Score:</b>\s*(\d+)') AS INT64)
            ) AS isdc_total,
            SAFE_CAST(REGEXP_EXTRACT(b.txt, r'ISDC Score[^<]*</strong>\s*([\d.]+)%') AS FLOAT64) AS isdc_pct,
            SAFE_CAST(REGEXP_EXTRACT(b.txt, r'MasseyCARE Score[^<]*</strong>\s*([\d.]+)%') AS FLOAT64) AS massey_pct,
            REGEXP_EXTRACT(b.txt, r'CriticalFailure:</strong>\s*(YES|NO)') AS critical_failure,
            REGEXP_CONTAINS(b.txt, r'insufficient transcript') AS has_insufficient_transcript,
            TRIM(REGEXP_EXTRACT(b.txt, r'<b>HIPAA risk:</b>\s*([^<]+)</p>')) AS hipaa_risk,
            REGEXP_EXTRACT(b.txt, r'font-size:42px;font-weight:700;color:#[0-9A-Fa-f]{6};line-height:1">([A-F])</span>') AS grade,
            TRIM(REGEXP_EXTRACT(b.txt, r'letter-spacing:0\.1em;color:rgba\(255,255,255,0\.7\);font-weight:600">([^<]+)</span>')) AS benchmark_label,
            IF(
              ARRAY_LENGTH(REGEXP_EXTRACT_ALL(b.txt, r'<td><strong>(?:\d\.\s*)?(Care|Diligence|Skill|Integrity)</strong></td>')) > 0,
              REGEXP_EXTRACT_ALL(b.txt, r'<td><strong>(?:\d\.\s*)?(Care|Diligence|Skill|Integrity)</strong></td>'),
              IF(
                ARRAY_LENGTH(REGEXP_EXTRACT_ALL(b.txt, r'<span style="font-size:12px;font-weight:600">([^<]+)</span>')) > 0,
                REGEXP_EXTRACT_ALL(b.txt, r'<span style="font-size:12px;font-weight:600">([^<]+)</span>'),
                REGEXP_EXTRACT_ALL(b.txt, r'<b>([A-Za-z &]+): Score \d / 4</b>')
              )
            ) AS pillar_names,
            ARRAY(
              SELECT SAFE_CAST(x AS INT64)
              FROM UNNEST(
                IF(
                  ARRAY_LENGTH(REGEXP_EXTRACT_ALL(b.txt, r'<td><strong>(?:\d\.\s*)?(?:Care|Diligence|Skill|Integrity)</strong></td>\s*<td>(\d)</td>')) > 0,
                  REGEXP_EXTRACT_ALL(b.txt, r'<td><strong>(?:\d\.\s*)?(?:Care|Diligence|Skill|Integrity)</strong></td>\s*<td>(\d)</td>'),
                  IF(
                    ARRAY_LENGTH(REGEXP_EXTRACT_ALL(b.txt, r'Score: (\d)/4')) > 0,
                    REGEXP_EXTRACT_ALL(b.txt, r'Score: (\d)/4'),
                    REGEXP_EXTRACT_ALL(b.txt, r'<b>[A-Za-z &]+: Score (\d) / 4</b>')
                  )
                )
              ) AS x
            ) AS pillar_scores,
            REGEXP_EXTRACT_ALL(b.txt, r'Pillar ([ISDC]) Average:') AS massey_names,
            ARRAY(
              SELECT SAFE_CAST(x AS FLOAT64)
              FROM UNNEST(REGEXP_EXTRACT_ALL(b.txt, r'Pillar [ISDC] Average: ([\d.]+) / 5')) AS x
            ) AS massey_scores,
            COALESCE(
              TRIM(REGEXP_EXTRACT(b.txt, r'LIVE_CONTACT_SENTIMENT:\s*([A-Za-z]+)')),
              TRIM(REGEXP_EXTRACT(REGEXP_EXTRACT(b.txt, r'(?s)(<b[^>]*>Customer</b>\s*<span.*?)</td>'), r'<span[^>]*>[^A-Za-z]*([A-Za-z \-]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'Customer Sentiment:</strong>\s*<span[^>]*>([^<]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'(?:Patient|Customer|Caller)</span>\s*<span[^>]*>([^<]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'<b>Customer:</b>\s*([^<]+)'))
            ) AS customer_sentiment,
            COALESCE(
              TRIM(REGEXP_EXTRACT(b.txt, r'LIVE_AGENT_SENTIMENT:\s*([A-Za-z]+)')),
              TRIM(REGEXP_EXTRACT(REGEXP_EXTRACT(b.txt, r'(?s)(<b[^>]*>Live Agent</b>\s*<span.*?)</td>'), r'<span[^>]*>[^A-Za-z]*([A-Za-z \-]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'Agent Sentiment:</strong>\s*<span[^>]*>([^<]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'>Agent</span>\s*<span[^>]*>([^<]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'<b>Agent:</b>\s*([^<]+)'))
            ) AS agent_sentiment,
            b.agentName AS agent,
            COALESCE(b.aiContactSentiment, b.xbertSentiment) AS ai_contact_sentiment,
            IF(b.aiContactSentiment IS NOT NULL, 'Bot at handoff', IF(b.xbertSentiment IS NOT NULL, 'Workflow label', NULL)) AS ai_contact_source,
            SUBSTR(b.aiContactEvidence, 1, 160) AS ai_contact_evidence,
            b.aiAgentSentiment AS ai_agent_sentiment,
            SUBSTR(b.aiAgentEvidence, 1, 160) AS ai_agent_evidence,
            SUBSTR(COALESCE(
              TRIM(REGEXP_EXTRACT(b.txt, r'LIVE_CONTACT_SENTIMENT_EVIDENCE:\s*([^<\r\n]+)')),
              TRIM(REGEXP_REPLACE(REGEXP_EXTRACT(REGEXP_EXTRACT(b.txt, r'(?s)(<b[^>]*>Customer</b>\s*<span.*?)</td>'), r'(?s)Evidence:</b>\s*(.*?)</div>'), r'<[^>]+>', ' '))
            ), 1, 160) AS live_contact_evidence,
            SUBSTR(COALESCE(
              TRIM(REGEXP_EXTRACT(b.txt, r'LIVE_AGENT_SENTIMENT_EVIDENCE:\s*([^<\r\n]+)')),
              TRIM(REGEXP_REPLACE(REGEXP_EXTRACT(REGEXP_EXTRACT(b.txt, r'(?s)(<b[^>]*>Live Agent</b>\s*<span.*?)</td>'), r'(?s)Evidence:</b>\s*(.*?)</div>'), r'<[^>]+>', ' '))
            ), 1, 160) AS live_agent_evidence,
            SUBSTR(TRIM(REGEXP_REPLACE(REGEXP_EXTRACT(REGEXP_EXTRACT(b.txt, r'(?s)(<b[^>]*>Customer</b>\s*<span.*?)</td>'), r'(?s)Trajectory:</strong>\s*(.*?)</div>'), r'<[^>]+>', ' ')), 1, 160) AS live_contact_trajectory,
            SUBSTR(TRIM(REGEXP_REPLACE(REGEXP_EXTRACT(REGEXP_EXTRACT(b.txt, r'(?s)(<b[^>]*>Live Agent</b>\s*<span.*?)</td>'), r'(?s)Trajectory:</strong>\s*(.*?)</div>'), r'<[^>]+>', ' ')), 1, 160) AS live_agent_trajectory,
            SAFE_CAST(REGEXP_EXTRACT(b.txt, r'LIVE AGENT ONLY</div><div[^>]*>\s*([0-9.]+)\s*%') AS FLOAT64) AS live_agent_score,
            SUBSTR(TRIM(REGEXP_EXTRACT(b.txt, r'<b>Reason:</b>\s*([^<]+)</p>')), 1, 160) AS reason,
            TRIM(REGEXP_EXTRACT(b.txt, r'<b>Disposition:</b>\s*([^<]+)</p>')) AS summary_disposition,
            COALESCE(
              TRIM(REGEXP_EXTRACT(b.txt, r'<b>Type:</b>\s*([^<]+)</p>')),
              TRIM(REGEXP_EXTRACT(b.txt, r'Interaction Type:</strong>\s*([^<]+)</li>'))
            ) AS interaction_type,
            REGEXP_EXTRACT_ALL(b.txt, r'font-size:12px;font-weight:700;color:#[0-9A-Fa-f]{6};margin-bottom:3px">([^<]+)</div>') AS coaching
          FROM (
            SELECT
              d.id,
              d.campaignName,
              d.channelType,
              d.transferred,
              d.talkTime,
              d.createdAt,
              d.terminationReason,
              IF(
                REGEXP_CONTAINS(JSON_VALUE(r.object, '$.data.qaRaw'), r'Hybrid Score|composite|Overall Score'),
                JSON_VALUE(r.object, '$.data.qaRaw'),
                JSON_VALUE(r.object, '$.summary')
              ) AS txt,
              IF(
                REGEXP_CONTAINS(JSON_VALUE(r.object, '$.data.qaRaw'), r'Hybrid Score|composite|Overall Score'),
                'Post-call QA',
                'Summary'
              ) AS source,
              COALESCE(NULLIF(u.userName, ''), JSON_VALUE(r.object, '$.agentUsername')) AS agentName,
              IF(STARTS_WITH(JSON_VALUE(r.object, '$.data.aiContactSentiment'), 'workitem.'), NULL, JSON_VALUE(r.object, '$.data.aiContactSentiment')) AS aiContactSentiment,
              IF(STARTS_WITH(JSON_VALUE(r.object, '$.data.aiContactSentimentEvidence'), 'workitem.'), NULL, JSON_VALUE(r.object, '$.data.aiContactSentimentEvidence')) AS aiContactEvidence,
              IF(STARTS_WITH(JSON_VALUE(r.object, '$.data.aiAgentSentiment'), 'workitem.'), NULL, JSON_VALUE(r.object, '$.data.aiAgentSentiment')) AS aiAgentSentiment,
              IF(STARTS_WITH(JSON_VALUE(r.object, '$.data.aiAgentSentimentEvidence'), 'workitem.'), NULL, JSON_VALUE(r.object, '$.data.aiAgentSentimentEvidence')) AS aiAgentEvidence,
              IF(STARTS_WITH(JSON_VALUE(r.object, '$.data.sentiment'), 'workitem.'), NULL, JSON_VALUE(r.object, '$.data.sentiment')) AS xbertSentiment
            FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
            JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
              ON r.callId = d.id
            LEFT JOIN (
              SELECT
                workitemId,
                userName
              FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS_USERS`
              WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
              QUALIFY ROW_NUMBER() OVER (PARTITION BY workitemId ORDER BY CAST(createdAt AS INT64) DESC) = 1
            ) AS u
              ON u.workitemId = d.id
            WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
              AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          ) AS b
          WHERE b.txt IS NOT NULL
            AND (REGEXP_CONTAINS(b.txt, 'composite') OR REGEXP_CONTAINS(b.txt, 'Overall Score') OR REGEXP_CONTAINS(b.txt, 'Hybrid Score'))
          ORDER BY b.createdAt DESC
          LIMIT 80
        ) AS e
        ORDER BY e.created_ms DESC
      ) AS ai_evals
    )
  ) AS ai_json
