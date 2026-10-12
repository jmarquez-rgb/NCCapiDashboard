DECLARE agent_days INT64 DEFAULT 730;

SELECT
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
