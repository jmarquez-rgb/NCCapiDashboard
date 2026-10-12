SELECT
  TO_JSON_STRING(
    STRUCT(
      FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', CURRENT_TIMESTAMP()) AS updated_at,
      ARRAY(
        SELECT AS STRUCT e.*
        FROM (
          SELECT
            SUBSTR(b.id, 1, 8) AS workitem,
            b.campaignName,
            b.channelType,
            b.transferred > 0 AS transferred_to_agent,
            ROUND(b.talkTime / 1000, 1) AS talk_sec,
            DATE(TIMESTAMP_MILLIS(b.createdAt), 'America/Phoenix') AS day,
            b.createdAt AS created_ms,
            IF(REGEXP_CONTAINS(b.summary, 'composite'), 'long', 'short') AS template,
            COALESCE(
              SAFE_CAST(REGEXP_EXTRACT(b.summary, r'>(\d{1,3})</div>\s*<div[^>]*>composite</div>') AS INT64),
              ROUND(SAFE_CAST(REGEXP_EXTRACT(b.summary, r'Overall Score:</b>\s*(\d+)') AS INT64) / 16 * 100)
            ) AS composite,
            REGEXP_EXTRACT(b.summary, r'font-size:42px;font-weight:700;color:#[0-9A-Fa-f]{6};line-height:1">([A-F])</span>') AS grade,
            TRIM(REGEXP_EXTRACT(b.summary, r'letter-spacing:0\.1em;color:rgba\(255,255,255,0\.7\);font-weight:600">([^<]+)</span>')) AS benchmark_label,
            IF(
              ARRAY_LENGTH(REGEXP_EXTRACT_ALL(b.summary, r'<span style="font-size:12px;font-weight:600">([^<]+)</span>')) > 0,
              REGEXP_EXTRACT_ALL(b.summary, r'<span style="font-size:12px;font-weight:600">([^<]+)</span>'),
              REGEXP_EXTRACT_ALL(b.summary, r'<b>([A-Za-z &]+): Score \d / 4</b>')
            ) AS pillar_names,
            ARRAY(
              SELECT SAFE_CAST(x AS INT64)
              FROM UNNEST(
                IF(
                  ARRAY_LENGTH(REGEXP_EXTRACT_ALL(b.summary, r'Score: (\d)/4')) > 0,
                  REGEXP_EXTRACT_ALL(b.summary, r'Score: (\d)/4'),
                  REGEXP_EXTRACT_ALL(b.summary, r'<b>[A-Za-z &]+: Score (\d) / 4</b>')
                )
              ) AS x
            ) AS pillar_scores,
            COALESCE(
              TRIM(REGEXP_EXTRACT(b.summary, r'(?:Patient|Customer|Caller)</span>\s*<span[^>]*>([^<]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.summary, r'<b>Customer:</b>\s*([^<]+)'))
            ) AS customer_sentiment,
            COALESCE(
              TRIM(REGEXP_EXTRACT(b.summary, r'>Agent</span>\s*<span[^>]*>([^<]+)</span>')),
              TRIM(REGEXP_EXTRACT(b.summary, r'<b>Agent:</b>\s*([^<]+)'))
            ) AS agent_sentiment,
            SUBSTR(TRIM(REGEXP_EXTRACT(b.summary, r'<b>Reason:</b>\s*([^<]+)</p>')), 1, 160) AS reason,
            TRIM(REGEXP_EXTRACT(b.summary, r'<b>Disposition:</b>\s*([^<]+)</p>')) AS summary_disposition,
            TRIM(REGEXP_EXTRACT(b.summary, r'<b>Type:</b>\s*([^<]+)</p>')) AS interaction_type,
            REGEXP_EXTRACT_ALL(b.summary, r'font-size:12px;font-weight:700;color:#[0-9A-Fa-f]{6};margin-bottom:3px">([^<]+)</div>') AS coaching
          FROM (
            SELECT
              d.id,
              d.campaignName,
              d.channelType,
              d.transferred,
              d.talkTime,
              d.createdAt,
              JSON_VALUE(r.object, '$.summary') AS summary
            FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
            JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
              ON r.callId = d.id
            WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
              AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          ) AS b
          WHERE b.summary IS NOT NULL
            AND (REGEXP_CONTAINS(b.summary, 'composite') OR REGEXP_CONTAINS(b.summary, 'Overall Score'))
          ORDER BY b.createdAt DESC
          LIMIT 60
        ) AS e
        ORDER BY e.created_ms DESC
      ) AS ai_evals
    )
  ) AS ai_json
