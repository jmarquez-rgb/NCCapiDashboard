DECLARE agent_days INT64 DEFAULT 730;

SELECT
  TO_JSON_STRING(
    STRUCT(
      FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', CURRENT_TIMESTAMP()) AS updated_at,
      30 AS window_days,
      agent_days AS agent_days,
      (
        SELECT AS STRUCT
          COUNT(*) AS workitems,
          COUNTIF(talkTime > 0) AS connected,
          COUNTIF(abandoned > 0) AS abandoned_calls,
          COUNTIF(transferred > 0) AS transferred_calls,
          ROUND(AVG(IF(talkTime > 0, talkTime, NULL)) / 1000, 1) AS talk_avg_sec,
          ROUND(AVG(IF(talkTime > 0, holdTime, NULL)) / 1000, 1) AS hold_avg_sec,
          ROUND(AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, wrapupTime, NULL)) / 1000, 1) AS acw_avg_sec_capped,
          ROUND(
            AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, talkTime + holdTime + wrapupTime, NULL)) / 1000,
            1
          ) AS aht_mean_sec_capped,
          ROUND(
            APPROX_QUANTILES(IF(talkTime > 0, talkTime + holdTime + wrapupTime, NULL), 100 IGNORE NULLS)[OFFSET(50)] / 1000,
            1
          ) AS aht_median_sec,
          COUNTIF(talkTime > 0 AND wrapupTime > 3600000) AS stuck_over_1h
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND channelType IN ('InboundCall', 'OutboundCall')
      ) AS kpis,
      (
        SELECT AS STRUCT
          COUNT(*) AS workitems,
          COUNTIF(talkTime > 0) AS handled,
          COUNTIF(talkTime > 0 AND wrapupTime <= 3600000) AS handled_capped,
          COUNTIF(abandoned > 0) AS abandoned,
          COUNTIF(transferred > 0) AS transferred,
          ROUND(AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, talkTime, NULL)) / 1000, 1) AS talk_avg_sec,
          ROUND(AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, holdTime, NULL)) / 1000, 1) AS hold_avg_sec,
          ROUND(AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, wrapupTime, NULL)) / 1000, 1) AS wrap_avg_sec,
          ROUND(AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, talkTime + holdTime + wrapupTime, NULL)) / 1000, 1) AS aht_mean_sec_capped,
          ROUND(
            APPROX_QUANTILES(IF(talkTime > 0 AND wrapupTime <= 3600000, talkTime + holdTime + wrapupTime, NULL), 100 IGNORE NULLS)[SAFE_OFFSET(50)] / 1000,
            1
          ) AS aht_median_sec,
          ROUND(
            APPROX_QUANTILES(IF(talkTime > 0 AND wrapupTime <= 3600000, talkTime + holdTime + wrapupTime, NULL), 100 IGNORE NULLS)[SAFE_OFFSET(90)] / 1000,
            1
          ) AS aht_p90_sec,
          COUNTIF(talkTime > 0 AND wrapupTime > 3600000) AS stuck_over_1h
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
      ) AS overall,
      ARRAY(
        SELECT AS STRUCT
          d.campaignName,
          COUNT(*) AS connected_calls,
          COUNTIF(JSON_VALUE(r.object, '$.summary') IS NOT NULL) AS with_summary,
          COUNTIF(REGEXP_CONTAINS(JSON_VALUE(r.object, '$.summary'), 'Overall Score')) AS short_isdc,
          COUNTIF(REGEXP_CONTAINS(JSON_VALUE(r.object, '$.summary'), 'composite')) AS long_composite
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
        JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
          ON r.callId = d.id
        WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND d.talkTime > 0
        GROUP BY d.campaignName
        ORDER BY connected_calls DESC
      ) AS coverage,
      ARRAY(
        SELECT AS STRUCT
          CASE
            WHEN JSON_VALUE(r.object, '$.summary') IS NULL THEN 'no summary'
            WHEN REGEXP_CONTAINS(JSON_VALUE(r.object, '$.summary'), 'Overall Score') THEN 'short ISDC'
            WHEN REGEXP_CONTAINS(JSON_VALUE(r.object, '$.summary'), 'composite') THEN 'long composite'
            ELSE 'other'
          END AS summary_type,
          COUNT(*) AS calls,
          ROUND(APPROX_QUANTILES(d.wrapupTime, 100)[OFFSET(25)] / 1000, 1) AS wrapup_p25_sec,
          ROUND(APPROX_QUANTILES(d.wrapupTime, 100)[OFFSET(50)] / 1000, 1) AS wrapup_median_sec,
          ROUND(APPROX_QUANTILES(d.wrapupTime, 100)[OFFSET(75)] / 1000, 1) AS wrapup_p75_sec
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
        JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
          ON r.callId = d.id
        WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND d.talkTime > 0
          AND d.wrapupTime <= 3600000
        GROUP BY summary_type
        ORDER BY calls DESC
      ) AS wrap_by_summary,
      ARRAY(
        SELECT AS STRUCT
          channelType,
          campaignName,
          dispositionName,
          ROUND(wrapupTime / 3600000, 1) AS wrap_hours
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND talkTime > 0
          AND wrapupTime > 3600000
        ORDER BY wrapupTime DESC
        LIMIT 10
      ) AS stuck_calls,
      ARRAY(
        SELECT AS STRUCT
          terminationReason,
          COUNT(*) AS workitems,
          COUNTIF(abandoned > 0) AS abandoned_workitems,
          COUNTIF(transferred > 0) AS transferred_workitems
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY terminationReason
        ORDER BY workitems DESC
      ) AS termination_codes,
      ARRAY(
        SELECT AS STRUCT
          channelType,
          terminationReason,
          COUNT(*) AS workitems,
          COUNTIF(abandoned > 0) AS abandoned_workitems,
          COUNTIF(transferred > 0) AS transferred_workitems
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY channelType, terminationReason
        ORDER BY workitems DESC
      ) AS termination_by_channel,
      ARRAY(
        SELECT AS STRUCT
          SUBSTR(d.id, 1, 8) AS workitem,
          d.channelType,
          ROUND(d.talkTime / 1000, 1) AS talk_sec,
          ROUND(d.wrapupTime / 1000, 1) AS wrapup_sec,
          CASE
            WHEN JSON_VALUE(r.object, '$.summary') IS NULL THEN 'none'
            WHEN REGEXP_CONTAINS(JSON_VALUE(r.object, '$.summary'), 'Overall Score') THEN 'short'
            WHEN REGEXP_CONTAINS(JSON_VALUE(r.object, '$.summary'), 'composite') THEN 'long'
            ELSE 'other'
          END AS summary_type,
          TRIM(REGEXP_EXTRACT(JSON_VALUE(r.object, '$.summary'), r'<b>Customer:</b>\s*([^<,.]+)')) AS customer_sentiment
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
        JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
          ON r.callId = d.id
        WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
          AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
          AND d.talkTime > 0
        ORDER BY d.createdAt DESC
        LIMIT 20
      ) AS recent_calls,
      ARRAY(
        SELECT AS STRUCT
          d.channelType,
          COUNT(*) AS workitems,
          COUNTIF(d.abandoned > 0) AS abandoned,
          COUNTIF(d.transferred > 0) AS transferred,
          COUNTIF(d.talkTime > 0) AS connected,
          COUNTIF(d.talkTime > 0 AND d.wrapupTime <= 3600000) AS handled_capped,
          ROUND(
            AVG(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.talkTime + d.holdTime + d.wrapupTime, NULL)) / 1000,
            1
          ) AS handle_avg_sec_capped,
          ROUND(AVG(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.talkTime, NULL)) / 1000, 1) AS talk_avg_sec,
          ROUND(AVG(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.holdTime, NULL)) / 1000, 1) AS hold_avg_sec,
          ROUND(AVG(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.wrapupTime, NULL)) / 1000, 1) AS wrap_avg_sec,
          ROUND(APPROX_QUANTILES(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.talkTime + d.holdTime + d.wrapupTime, NULL), 100 IGNORE NULLS)[SAFE_OFFSET(50)] / 1000, 1) AS handle_median_sec,
          ROUND(APPROX_QUANTILES(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.talkTime + d.holdTime + d.wrapupTime, NULL), 100 IGNORE NULLS)[SAFE_OFFSET(90)] / 1000, 1) AS handle_p90_sec,
          ROUND(AVG(IF(d.workitemTime > 0 AND d.wrapupTime <= 3600000, d.workitemTime, NULL)) / 1000, 1) AS open_avg_sec,
          ROUND(APPROX_QUANTILES(IF(d.workitemTime > 0 AND d.wrapupTime <= 3600000, d.workitemTime, NULL), 100 IGNORE NULLS)[SAFE_OFFSET(50)] / 1000, 1) AS open_median_sec,
          ROUND(AVG(d.agentMessageCount), 1) AS agent_msgs_avg,
          ROUND(AVG(d.consumerMessageCount), 1) AS customer_msgs_avg,
          ROUND(AVG(d.botMessageCount), 1) AS bot_msgs_avg,
          COUNTIF(r.callId IS NOT NULL) AS joined_workitems,
          COUNTIF(JSON_VALUE(r.object, '$.summary') IS NOT NULL) AS with_summary
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
        LEFT JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
          ON r.callId = d.id
          AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY d.channelType
        ORDER BY workitems DESC
      ) AS channels,
      ARRAY(
        SELECT AS STRUCT * FROM (
        SELECT
          DATE(TIMESTAMP_MILLIS(createdAt), 'America/Phoenix') AS day,
          COUNT(*) AS workitems,
          COUNTIF(channelType IN ('InboundCall', 'OutboundCall')) AS voice,
          COUNTIF(channelType IN ('PredictiveCall', 'ProgressiveCall', 'PredictiveSMS')) AS dialer,
          COUNTIF(channelType = 'Chat') AS chat,
          COUNTIF(channelType IN ('InboundSMS', 'OutboundSMS')) AS sms,
          COUNTIF(channelType IN ('Email', 'OutboundEmail')) AS email,
          COUNTIF(channelType = 'Survey') AS survey,
          COUNTIF(abandoned > 0) AS abandoned
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY day
        ORDER BY day
        )
      ) AS daily,
      ARRAY(
        SELECT AS STRUCT * FROM (
        SELECT
          EXTRACT(DAYOFWEEK FROM DATE(TIMESTAMP_MILLIS(createdAt), 'America/Phoenix')) AS dow,
          EXTRACT(HOUR FROM DATETIME(TIMESTAMP_MILLIS(createdAt), 'America/Phoenix')) AS hour,
          COUNT(*) AS workitems
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY dow, hour
        ORDER BY dow, hour
        )
      ) AS hourly,
      ARRAY(
        SELECT AS STRUCT * FROM (
        SELECT
          dispositionName,
          COUNT(*) AS workitems
        FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
        WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND dispositionName IS NOT NULL
        GROUP BY dispositionName
        ORDER BY workitems DESC
        LIMIT 12
        )
      ) AS dispositions,
      ARRAY(
        SELECT AS STRUCT
        INITCAP(
          REPLACE(
            SPLIT(SPLIT(COALESCE(JSON_VALUE(r.object, '$.agentUsername'), 'no.agent'), '@')[OFFSET(0)], '+')[OFFSET(0)],
            '.',
            ' '
          )
        ) AS agent_name,
        SPLIT(COALESCE(JSON_VALUE(r.object, '$.agentUsername'), 'no.agent'), '@')[OFFSET(0)] AS agent_login,
        COUNT(*) AS workitems,
        COUNTIF(d.channelType IN ('InboundCall', 'OutboundCall', 'PredictiveCall', 'ProgressiveCall')) AS calls,
        COUNTIF(d.channelType = 'Chat') AS chats,
        COUNTIF(d.channelType IN ('InboundSMS', 'OutboundSMS', 'PredictiveSMS')) AS sms,
        COUNTIF(d.channelType IN ('Email', 'OutboundEmail')) AS emails,
        COUNTIF(d.talkTime > 0) AS connected_calls,
        COUNTIF(d.transferred > 0) AS transferred,
        ROUND(
          AVG(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.talkTime + d.holdTime + d.wrapupTime, NULL)) / 1000,
          1
        ) AS handle_avg_sec_capped,
        COUNTIF(JSON_VALUE(r.object, '$.summary') IS NOT NULL) AS with_summary,
        MIN(DATE(TIMESTAMP_MILLIS(d.createdAt), 'America/Phoenix')) AS first_seen,
        MAX(DATE(TIMESTAMP_MILLIS(d.createdAt), 'America/Phoenix')) AS last_seen
      FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS` AS d
      JOIN `thrio-prod-4258998.4258998.REPORTS_WORKITEMS` AS r
        ON r.callId = d.id
      WHERE d._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL agent_days DAY)
        AND r._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL agent_days DAY)
      GROUP BY agent_name, agent_login
      ORDER BY workitems DESC
      LIMIT 200
      ) AS agents
    )
  ) AS data_json
