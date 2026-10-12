SELECT
  terminationReason,
  COUNT(*) AS workitems,
  COUNTIF(abandoned > 0) AS abandoned_workitems,
  COUNTIF(transferred > 0) AS transferred_workitems
FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY terminationReason
ORDER BY workitems DESC
