/**
 * Handler for the single Case trigger (force-app/main/default/triggers/CaseTrigger.trigger).
 *
 * Why each event is used
 *  before insert : classify, prioritize and route the new case by setting fields in memory (no extra DML, no recursion).
 *  before update : re-evaluate only when Subject, Description or AI_Failed_Attempts__c changed; may escalate/re-route.
 *  after insert  : the record Id exists now, so audit-log entries can reference the case.
 *  after update  : audit-log newly escalated cases and re-classified cases. NO DML on Case here (no recursion).
 *
 * Repeated-processing protection: Intake_Processed__c (insert), change detection (update), and the Escalation
 * flag logic in CaseIntelligenceService (an already-escalated case is never escalated or re-notified again).
 * Kill switch: Support_Setting__mdt "Default".Case_Automation_Enabled__c, plus the @TestVisible bypass for tests.
 */
public with sharing class CaseTriggerHandler {
    @TestVisible private static Boolean bypass = false;
    /** Test hook that makes the intelligence layer fail, to prove a failure never blocks case creation. */
    @TestVisible private static Boolean simulateFailure = false;

    public static void run(TriggerOperation operation, List<Case> newCases, Map<Id, Case> oldMap) {
        if (bypass || newCases == null || newCases.isEmpty() || !SupportConstants.isCaseAutomationEnabled()) {
            return;
        }
        switch on operation {
            when BEFORE_INSERT {
                beforeWrite(newCases, null);
            }
            when BEFORE_UPDATE {
                beforeWrite(newCases, oldMap);
            }
            when AFTER_INSERT {
                afterWrite(newCases, null);
            }
            when AFTER_UPDATE {
                afterWrite(newCases, oldMap);
            }
            when else {
                // before/after delete and undelete are not handled
            }
        }
    }

    private static void beforeWrite(List<Case> cases, Map<Id, Case> oldMap) {
        try {
            if (simulateFailure) {
                throw new SupportException('Simulated failure');
            }
            CaseIntelligenceService.applyIntake(cases, oldMap);
        } catch (Exception e) {
            // A failure in the intelligence layer must never block case creation. Record it (no customer data) and continue.
            AIInteractionLogService.LogEntry failed = new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_CLASSIFICATION, SupportConstants.OUTCOME_FAILED, SupportConstants.SOURCE_RULES);
            failed.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            AIInteractionLogService.log(failed);
        }
    }

    private static void afterWrite(List<Case> cases, Map<Id, Case> oldMap) {
        Boolean isInsert = oldMap == null;
        List<AIInteractionLogService.LogEntry> entries = new List<AIInteractionLogService.LogEntry>();
        for (Case c : cases) {
            Case old = isInsert ? null : oldMap.get(c.Id);
            Boolean classified = isInsert
                ? (c.Intake_Processed__c == true && c.Issue_Category__c != null)
                : CaseIntelligenceService.consumeReprocessed(c.Id);
            Boolean newlyEscalated = c.Human_Handoff_Required__c == true && (isInsert || old.Human_Handoff_Required__c != true);

            if (classified) {
                entries.add(AIInteractionLogService.fromCase(c, SupportConstants.TYPE_CLASSIFICATION, SupportConstants.OUTCOME_SUCCESS, SupportConstants.SOURCE_RULES));
            }
            if (newlyEscalated && !SupportEscalationService.isEscalationLoggedByService(c.Id)) {
                AIInteractionLogService.LogEntry escalation = AIInteractionLogService.fromCase(c, SupportConstants.TYPE_ESCALATION, SupportConstants.OUTCOME_ESCALATED, SupportConstants.SOURCE_RULES);
                escalation.recommendedAction = 'Escalated: ' + c.Escalation_Reason__c;
                entries.add(escalation);
            }
        }
        AIInteractionLogService.log(entries); // one DML statement for the whole batch
    }
}
