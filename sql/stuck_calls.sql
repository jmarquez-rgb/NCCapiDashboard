SELECT
  campaignName,
  dispositionName,
  ROUND(wrapupTime / 3600000, 1) AS wrap_hours
FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND channelType IN ('InboundCall', 'OutboundCall')
  AND talkTime > 0
  AND wrapupTime > 3600000
ORDER BY wrapupTime DESC
LIMIT 10
