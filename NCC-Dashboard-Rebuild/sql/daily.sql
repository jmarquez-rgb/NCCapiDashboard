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
