# Data dictionary

## Case (custom fields)
| Field | Type | Values / notes |
|---|---|---|
| `Issue_Category__c` | Restricted picklist | Billing, Technical, Account Access, Security, Shipping, Product Defect, General |
| `Sentiment__c` | Picklist | Positive, Neutral, Negative, Unknown |
| `AI_Summary__c` | Long text (4000) | Rule-based or reviewed summary |
| `AI_Recommended_Priority__c` | Picklist | High, Medium, Low (a recommendation, not authority) |
| `AI_Recommended_Action__c` | Text (255) | Suggested next step |
| `Human_Handoff_Required__c` | Checkbox | True when a person must take over |
| `Escalation_Reason__c` | Picklist | Security Concern, Widespread Outage, Customer Requested Human, Repeated AI Failure, Insufficient Knowledge, Premium Account High Priority, Manual Escalation |
| `Escalation_Notified__c` | Checkbox | Duplicate-notification guard |
| `Intake_Processed__c` | Checkbox | Intake idempotency guard |
| `AI_Failed_Attempts__c` | Number(2,0) | Validation rule keeps it >= 0 |

## Account
`Support_Tier__c` picklist: Standard, Premium.

## AI_Interaction_Log__c (`AIL-{0000}`)
`Case__c` (Lookup, SetNull), `Interaction_Type__c`, `Request_Category__c`, `Suggested_Priority__c`, `Sentiment__c`, `Recommended_Action__c`, `Human_Handoff_Required__c`, `Outcome__c` (Success, Insufficient Evidence, Escalated, Failed, Blocked), `Source__c` (Rules, Agentforce, Prompt Builder, External LLM, User Interface), `Error_Message__c`. Sharing model: Read. Text is sanitised and e-mails / digit runs are masked.

## Custom metadata
- `Queue_Mapping__mdt`: `Queue_Developer_Name__c`, `Is_Active__c`; one record per route key (Billing, Technical, Account_Access, Security, Shipping, Product_Defect, General, Urgent_Escalation).
- `Support_Setting__mdt` (record `Default`): `Case_Automation_Enabled__c`, `Handoff_Failed_Attempt_Threshold__c` (2), `Knowledge_Min_Matched_Terms__c` (2), `Knowledge_Max_Results__c` (5), `External_LLM_Enabled__c` (false), `External_LLM_Model__c`.

## Queues
Billing_Support, Technical_Support, Account_Access_Support, Security_Response, Shipping_Support, Product_Defect_Support, General_Support, Urgent_Escalations (Case-enabled; members must be added manually).
