SELECT
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
  AND d.channelType IN ('InboundCall', 'OutboundCall')
  AND d.talkTime > 0
GROUP BY d.campaignName
ORDER BY connected_calls DESC
