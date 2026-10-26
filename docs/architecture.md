# Architecture

SmartSupport AI is a **deterministic-first** support automation core with optional AI layers. Rules decide priority, routing, escalation and authorization; AI (Agentforce, Prompt Builder, external LLM) may only *suggest*, and every suggestion is validated and logged.

```mermaid
flowchart LR
  C[Customer / agent] -->|creates Case| T[CaseTrigger]
  T --> H[CaseTriggerHandler]
  H --> I[CaseIntelligenceService]
  I --> R[CaseRoutingRules<br/>pure, keyword rules]
  I --> Q[QueueRoutingService<br/>Queue_Mapping__mdt]
  H --> E[SupportEscalationService]
  E --> N[Flow: Escalation Notification]
  N --> NA[FlowActionEscalationNotification]
  F1[Flow: Case Intake safety net] --> FA[FlowActionCaseIntake] --> I
  AG[Agentforce agent] --> A[AgentAction* invocables] --> S[AgentforceActionService]
  S --> K[KnowledgeSearchService<br/>RAG-style retrieval]
  S --> CA[CaseActionService]
  S --> E
  LWC[4 LWCs] --> CT[SupportAssistantController / SupportDashboardController] --> S
  I & K & CA & E --> L[AIInteractionLogService<br/>AI_Interaction_Log__c]
  LLM[(Optional: external LLM)] -.-> X[ExternalLLMService] -.-> S
```

## Layers
| Layer | Classes | Responsibility |
|---|---|---|
| Entry points | `CaseTrigger`, 2 record-triggered Flows, screen flow, 7 agent actions, LWC controllers | Thin; validate input, call services |
| Services | `CaseIntelligenceService`, `KnowledgeSearchService`, `SupportEscalationService`, `CaseActionService`, `CustomerContextService`, `QueueRoutingService`, `AIInteractionLogService` | Business logic, USER_MODE data access |
| Rules | `CaseRoutingRules` | Pure functions; no DML/SOQL; fully unit-testable |
| Config | `SupportConstants`, `Support_Setting__mdt`, `Queue_Mapping__mdt` | Thresholds and queue names; no hard-coded Ids |
| Audit | `AI_Interaction_Log__c` | Sanitised, PII-scrubbed log; Lookup to Case with SetNull so history can be retained |

## Decision precedence
Category: Security > Outage > Account Access > Billing > Shipping > Product Defect > Technical > General.
Escalation reason: Security > Widespread Outage > Customer Requested Human > Repeated AI Failure > Premium + High priority. The first reason is kept; later signals never overwrite it.

## Key design decisions
- **One invocable class per action** (Apex allows one `@InvocableMethod` per class).
- **Idempotency**: `Intake_Processed__c` and `Escalation_Notified__c` prevent reprocessing and duplicate notifications.
- **Insufficient knowledge**: retrieval returns `INSUFFICIENT_EVIDENCE` and never a fabricated answer; the caller is told to hand off to a human.
- **Optional modules** (Data Cloud, external LLM) sit outside the core manifest, so the core deploys on any org with Service Cloud and Knowledge not required for deployment.
