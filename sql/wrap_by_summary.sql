SELECT
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
  AND d.channelType IN ('InboundCall', 'OutboundCall')
  AND d.talkTime > 0
  AND d.wrapupTime <= 3600000
GROUP BY summary_type
ORDER BY CASE summary_type
  WHEN 'no summary' THEN 1
  WHEN 'short ISDC' THEN 2
  WHEN 'long composite' THEN 3
  ELSE 4
END
