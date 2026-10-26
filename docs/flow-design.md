# Flow design

All three flows are deployed with status **Draft** and must be reviewed and activated manually (Setup > Flows). Flows contain no business logic: they call Apex actions that share code with the trigger.

| Flow | Type | Trigger | Purpose |
|---|---|---|---|
| SmartSupport Case Intake | Record-triggered, after save | Case created | Safety net: runs `FlowActionCaseIntake` for cases where `Intake_Processed__c = false` (e.g. created while the trigger was bypassed). Fault path stores the error; case creation is never blocked. |
| SmartSupport Escalation Notification | Record-triggered, after save | Case with `Human_Handoff_Required__c = true` and `Escalation_Notified__c = false` | Calls `FlowActionEscalationNotification` (one custom notification) then marks notified. Fault path leaves the flag false so a later change can retry. |
| SmartSupport AI Assisted Resolution | Screen flow | Launched by an agent from a case | Calls `AgentActionSummarizeCase`, shows the suggestion, and posts an **internal** comment only after the agent presses the button. If the summary fails, shows a manual fallback. |

Design notes: the trigger and Flow A overlap deliberately; `Intake_Processed__c` makes the second run a no-op. After activating, test in a sandbox: set `Support_Setting__mdt.Case_Automation_Enabled__c` to false, create a case, set it back to true, and confirm the intake flow (or a later edit) processes it exactly once. Both the trigger and Flow A honour that kill switch.
