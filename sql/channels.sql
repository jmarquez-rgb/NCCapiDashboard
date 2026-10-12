SELECT
  d.channelType,
  COUNT(*) AS workitems,
  COUNTIF(d.abandoned > 0) AS abandoned,
  COUNTIF(d.transferred > 0) AS transferred,
  COUNTIF(d.talkTime > 0) AS connected,
  ROUND(
    AVG(IF(d.talkTime > 0 AND d.wrapupTime <= 3600000, d.talkTime + d.holdTime + d.wrapupTime, NULL)) / 1000,
    1
  ) AS handle_avg_sec_capped,
  ROUND(AVG(IF(d.workitemTime > 0 AND d.wrapupTime <= 3600000, d.workitemTime, NULL)) / 1000, 1) AS open_avg_sec,
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
