SELECT
  COUNT(*) AS workitems,
  COUNTIF(talkTime > 0) AS connected,
  COUNTIF(abandoned > 0) AS abandoned_calls,
  COUNTIF(transferred > 0) AS transferred_calls,
  ROUND(AVG(IF(talkTime > 0, talkTime, NULL)) / 1000, 1) AS talk_avg_sec,
  ROUND(AVG(IF(talkTime > 0, holdTime, NULL)) / 1000, 1) AS hold_avg_sec,
  ROUND(
    AVG(IF(talkTime > 0 AND wrapupTime <= 3600000, wrapupTime, NULL)) / 1000,
    1
  ) AS acw_avg_sec_capped,
  ROUND(
    AVG(
      IF(
        talkTime > 0 AND wrapupTime <= 3600000,
        talkTime + holdTime + wrapupTime,
        NULL
      )
    ) / 1000,
    1
  ) AS aht_mean_sec_capped,
  ROUND(
    APPROX_QUANTILES(
      IF(talkTime > 0, talkTime + holdTime + wrapupTime, NULL),
      100 IGNORE NULLS
    )[OFFSET(50)] / 1000,
    1
  ) AS aht_median_sec,
  COUNTIF(talkTime > 0 AND wrapupTime > 3600000) AS stuck_over_1h
FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND channelType IN ('InboundCall', 'OutboundCall')
