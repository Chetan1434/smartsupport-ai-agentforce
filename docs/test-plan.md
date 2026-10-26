# Test plan and acceptance checklist

Run automated tests first: `scripts/run-tests.sh <alias>` and `npm run test:unit`. Then perform the manual checks below and record the **actual result** (left blank on purpose; nothing here has been executed).

| # | Scenario | Expected | Actual | Pass? |
|---|---|---|---|---|
| 1 | Create case "Password reset link never arrives" | Category Account Access, queue Account_Access_Support, no handoff | | |
| 2 | Case "Charged twice on invoice, refund" | Billing, Billing_Support; Negative sentiment | | |
| 3 | Case "Service is down for all users" | Priority High, Widespread Outage, Urgent_Escalations, handoff, one notification | | |
| 4 | Case "unauthorized access, data breach" | Security, Security_Response, Security Concern, handoff | | |
| 5 | Case "I want to speak to a human" | Customer Requested Human, handoff | | |
| 6 | Record two failed attempts via Escalate action | Repeated AI Failure, handoff | | |
| 7 | Knowledge Assistant: "How do I reset my password?" (article published) | Article returned with evidence | | |
| 8 | Knowledge Assistant: "refund policy for enterprise" | Insufficient evidence + handoff offer, no invented answer | | |
| 9 | Re-save an escalated case several times | Exactly one notification; first reason unchanged | | |
| 10 | Status lookup by case number only (agent action) | Refused; needs verified e-mail | | |
| 11 | User without SmartSupport permission set opens the app | No data / permission message | | |
| 12 | Change a Queue_Mapping record to another queue | New cases route to it with no code change | | |
| 13 | Set Case_Automation_Enabled__c = false | New cases are not auto-processed | | |
