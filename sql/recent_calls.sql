SELECT
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
  AND d.channelType IN ('InboundCall', 'OutboundCall')
  AND d.talkTime > 0
ORDER BY d.createdAt DESC
LIMIT 20
