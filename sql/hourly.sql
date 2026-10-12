SELECT
  EXTRACT(DAYOFWEEK FROM DATE(TIMESTAMP_MILLIS(createdAt), 'America/Phoenix')) AS dow,
  EXTRACT(HOUR FROM DATETIME(TIMESTAMP_MILLIS(createdAt), 'America/Phoenix')) AS hour,
  COUNT(*) AS workitems
FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND channelType IN ('InboundCall', 'OutboundCall')
GROUP BY dow, hour
ORDER BY dow, hour
