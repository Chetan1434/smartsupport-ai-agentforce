# Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Cases land with the creator as owner | Queue not found or mapping inactive | Check the Queue exists (deployed) and `Queue_Mapping__mdt.Is_Active__c`; routing falls back safely and logs the reason |
| No notification arrives | Flow still Draft, or the custom notification type is not enabled for your user | Activate "SmartSupport Escalation Notification"; check Setup > Notification Builder |
| Knowledge search always "insufficient evidence" | Knowledge not enabled, no published articles, user lacks Knowledge access | Enable Lightning Knowledge, publish samples (`data/knowledge-samples`), assign Knowledge User |
| Deploy error on a Flow property | Org older than API 65.0 | Deploy to a current org/scratch org, or lower `sourceApiVersion` and fix reported properties |
| Permission errors in the LWCs | Permission set not assigned | `sf org assign permset --name SmartSupport_Admin` |
| Apex test fails on "no access user" | Profile "Minimum Access - Salesforce" missing | Those tests return early when the profile is absent |
| Agent action not visible | Class not on the agent's running user's permission set | Assign SmartSupport_Agentforce_User |
| External LLM returns DISABLED | `External_LLM_Enabled__c` false | See optional/external-llm/README.md |
