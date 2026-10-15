/* NCC usage drill-down data for the dashboard: one JSON cell, last 90 days, by day and campaign (Phoenix time) */
WITH workitems AS (
  SELECT
    id AS workitemId,
    COALESCE(campaignName, '') AS campaign,
    channelType,
    createdAt,
    GREATEST(COALESCE(terminatedAt, createdAt) - createdAt, 0) AS durationMs,
    COALESCE(talkTime, 0) AS talkMs,
    COALESCE(consumerMessageCount, 0) AS consumerMessages,
    COALESCE(agentMessageCount, 0) AS agentMessages,
    COALESCE(botMessageCount, 0) AS botMessages,
    COALESCE(smsConsumerMessageCount, 0) + COALESCE(smsAgentMessageCount, 0) + COALESCE(smsBotMessageCount, 0) AS smsMessages,
    COALESCE(smsAgentMessageCount, 0) AS smsAgentMessages,
    CASE
      WHEN channelType IN ('InboundCall', 'OutboundCall', 'InboundExtensionCall', 'OutboundExtensionCall', 'PredictiveCall', 'PreviewCall', 'ProgressiveCall') THEN 'Voice'
      WHEN channelType IN ('InboundSMS', 'OutboundSMS') THEN 'SMS'
      WHEN channelType IN ('Email', 'OutboundEmail') THEN 'Email'
      WHEN channelType = 'Chat' THEN 'Chat'
      ELSE 'Other'
    END AS channelGroup,
    channelType IN ('InboundCall', 'InboundExtensionCall') AS isInbound,
    (channelType = 'OutboundCall' AND terminationReason = 20 AND COALESCE(talkTime, 0) = 0) AS isAiLeg
  FROM `thrio-prod-4258998.4258998.DATA_WORKITEMS`
  WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 93 DAY)
    AND createdAt >= UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY))
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY terminatedAt DESC) = 1
),

daily AS (
  SELECT
    FORMAT_DATE('%Y-%m-%d', DATE(TIMESTAMP_MILLIS(createdAt), 'America/Phoenix')) AS day,
    campaign,
    COUNTIF(channelGroup = 'Voice' AND NOT isAiLeg AND isInbound) AS inbound_calls,
    COUNTIF(channelGroup = 'Voice' AND NOT isAiLeg AND NOT isInbound) AS outbound_calls,
    ROUND(SUM(IF(channelGroup = 'Voice' AND NOT isAiLeg AND isInbound AND durationMs <= 14400000, durationMs, 0)) / 60000, 1) AS inbound_minutes,
    ROUND(SUM(IF(channelGroup = 'Voice' AND NOT isAiLeg AND NOT isInbound AND durationMs <= 14400000, durationMs, 0)) / 60000, 1) AS outbound_minutes,
    ROUND(SUM(IF(channelGroup = 'Voice' AND NOT isAiLeg, talkMs, 0)) / 60000, 1) AS connected_minutes,
    COUNTIF(channelGroup = 'Voice' AND NOT isAiLeg AND durationMs > 14400000) AS calls_over_4h,
    COUNTIF(isAiLeg) AS ai_leg_calls,
    ROUND(SUM(IF(isAiLeg AND durationMs <= 14400000, durationMs, 0)) / 60000, 1) AS ai_leg_minutes,
    COUNTIF(channelGroup = 'SMS') AS sms_conversations,
    SUM(IF(channelGroup = 'SMS', smsMessages, 0)) AS sms_messages,
    COUNTIF(channelGroup = 'SMS' AND smsAgentMessages > 0) AS sms_replied,
    SUM(IF(channelGroup = 'SMS', smsAgentMessages, 0)) AS sms_agent_replies,
    COUNTIF(channelType = 'Email') AS emails_in,
    COUNTIF(channelType = 'OutboundEmail') AS emails_out,
    COUNTIF(channelGroup = 'Chat') AS chats,
    COUNTIF(channelGroup = 'Chat' AND consumerMessages > 0) AS chats_with_customer,
    COUNTIF(channelGroup = 'Chat' AND agentMessages > 0) AS chats_replied_agent,
    COUNTIF(channelGroup = 'Chat' AND botMessages > 0) AS chats_replied_bot
  FROM workitems
  GROUP BY day, campaign
)

SELECT
  TO_JSON_STRING(
    STRUCT(
      FORMAT_TIMESTAMP('%m/%d/%Y %H:%M', CURRENT_TIMESTAMP(), 'America/Phoenix') AS updated_at,
      ARRAY(SELECT AS STRUCT * FROM daily ORDER BY day DESC, campaign) AS usage_rows
    )
  ) AS usage_json
