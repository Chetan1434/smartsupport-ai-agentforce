/**
 * Case intelligence: turns the deterministic rules (CaseRoutingRules) into case field values and read-only insights.
 *
 *  - applyIntake():       used by the Case trigger (before insert / before update). Mutates the in-memory Case
 *                         records only (no DML), bulk safe: one premium-account query and two queue queries total.
 *  - analyze():           used by LWC and Agentforce actions. Reads one case in USER mode, returns an Insight, no DML.
 *  - summarizeAndSave():  persists the summary / recommendation fields in USER mode and writes an audit log.
 *
 * Rules for what automation may change on its own:
 *   Priority             raised to High ONLY for deterministic urgent signals (security, outage). Never lowered.
 *   AI_Recommended_*     always refreshed (they are recommendations).
 *   Human handoff/owner  set only when an escalation rule matches; the first Escalation_Reason__c is kept.
 */
public with sharing class CaseIntelligenceService {

    /** Read-only result shown in the UI and returned by agent actions. */
    public class Insight {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String issueCategory;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String summary;
        @AuraEnabled public String recommendedPriority;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public String recommendedQueue;
        @AuraEnabled public Boolean humanHandoffRequired = false;
        @AuraEnabled public Boolean escalationRecommended = false;
        @AuraEnabled public String escalationReason;
        @AuraEnabled public String explanation;
        @AuraEnabled public Integer failedAttempts = 0;
        @AuraEnabled public List<String> troubleshootingSteps = new List<String>();
        @AuraEnabled public String source = SupportConstants.SOURCE_RULES;
    }

    /** Ids of existing cases re-evaluated by the rules in this transaction (consumed by the trigger's after phase). */
    private static Set<Id> reprocessedCaseIds = new Set<Id>();

    /** True once per re-evaluation: lets the after-update phase audit real re-classifications only. */
    public static Boolean consumeReprocessed(Id caseId) {
        return reprocessedCaseIds.remove(caseId);
    }

    // ---------------------------------------------------------------------------------------------
    // Trigger entry point
    // ---------------------------------------------------------------------------------------------

    /**
     * Classifies, prioritizes and routes cases in memory.
     * @param cases  Trigger.new
     * @param oldMap Trigger.oldMap (null on insert)
     * @return number of cases that were processed
     */
    public static Integer applyIntake(List<Case> cases, Map<Id, Case> oldMap) {
        if (cases == null || cases.isEmpty()) {
            return 0;
        }
        Boolean isInsert = oldMap == null;

        List<Case> candidates = new List<Case>();
        Set<Id> accountIds = new Set<Id>();
        for (Case c : cases) {
            if (shouldProcess(c, isInsert ? null : oldMap.get(c.Id))) {
                candidates.add(c);
                if (c.AccountId != null) {
                    accountIds.add(c.AccountId);
                }
            }
        }
        if (candidates.isEmpty()) {
            return 0;
        }

        Set<Id> premiumAccounts = CustomerContextService.premiumAccountIds(accountIds);
        Integer threshold = SupportConstants.failedAttemptThreshold();

        List<CaseRoutingRules.Decision> decisions = new List<CaseRoutingRules.Decision>();
        Set<String> routeKeys = new Set<String>();
        for (Case c : candidates) {
            CaseRoutingRules.Decision d = CaseRoutingRules.evaluate(inputFor(c, premiumAccounts.contains(c.AccountId), threshold));
            decisions.add(d);
            routeKeys.add(d.routeKey);
            routeKeys.add(d.escalationRouteKey);
        }
        Map<String, Id> queues = QueueRoutingService.resolve(routeKeys);

        for (Integer i = 0; i < candidates.size(); i++) {
            applyDecision(candidates[i], decisions[i], queues, isInsert);
            if (!isInsert) {
                reprocessedCaseIds.add(candidates[i].Id);
            }
        }
        return candidates.size();
    }

    /** Insert: every case not yet processed. Update: only when the text or the failed-attempt counter changed. */
    @TestVisible
    private static Boolean shouldProcess(Case c, Case oldCase) {
        if (oldCase == null) {
            return c.Intake_Processed__c != true;
        }
        return c.Subject != oldCase.Subject
            || c.Description != oldCase.Description
            || c.AI_Failed_Attempts__c != oldCase.AI_Failed_Attempts__c;
    }

    private static void applyDecision(Case c, CaseRoutingRules.Decision d, Map<String, Id> queues, Boolean isInsert) {
        c.Issue_Category__c = d.category;
        c.Sentiment__c = d.sentiment;
        c.AI_Recommended_Priority__c = d.recommendedPriority;
        c.AI_Recommended_Action__c = truncate(d.suggestedAction, 255);
        c.AI_Summary__c = buildSummary(c.Subject, c.Description, d);

        // Deterministic urgent rules may RAISE the standard priority. Recommendations never change it.
        if (d.isUrgentByRule() && CaseRoutingRules.priorityRank(c.Priority) < CaseRoutingRules.priorityRank(SupportConstants.PRIORITY_HIGH)) {
            c.Priority = SupportConstants.PRIORITY_HIGH;
        }

        Boolean newlyEscalated = false;
        if (d.mustEscalate()) {
            if (c.Human_Handoff_Required__c != true) {
                newlyEscalated = true;
                c.Human_Handoff_Required__c = true;
                c.IsEscalated = true;
                c.Escalation_Notified__c = false; // lets the notification Flow fire once for this new escalation
            }
            if (String.isBlank(c.Escalation_Reason__c)) {
                c.Escalation_Reason__c = d.escalationReason;
            }
        }

        // Routing: a queue is assigned only when a valid, Case-enabled queue mapping exists.
        Id categoryQueue = queues.get(d.routeKey);
        Id escalationQueue = queues.get(d.escalationRouteKey);
        Id target = d.mustEscalate() ? (escalationQueue != null ? escalationQueue : categoryQueue) : categoryQueue;
        if (target != null) {
            if (isInsert && !QueueRoutingService.isQueueId(c.OwnerId)) {
                c.OwnerId = target;
            } else if (!isInsert && newlyEscalated) {
                c.OwnerId = target;
            }
        }
        c.Intake_Processed__c = true;
    }

    // ---------------------------------------------------------------------------------------------
    // Read-only analysis (LWC and Agentforce)
    // ---------------------------------------------------------------------------------------------

    /** Analyses one case with the caller's permissions. Throws SupportException when the case is not accessible. */
    public static Insight analyze(Id caseId) {
        Case c = loadCase(caseId);
        Set<Id> premium = c.AccountId == null ? new Set<Id>() : CustomerContextService.premiumAccountIds(new Set<Id>{ c.AccountId });
        CaseRoutingRules.Decision d = CaseRoutingRules.evaluate(inputFor(c, premium.contains(c.AccountId), SupportConstants.failedAttemptThreshold()));
        return toInsight(c, d);
    }

    /** Analyses a case and stores the summary and recommendations on it (USER mode). Writes an audit log entry. */
    public static Insight summarizeAndSave(Id caseId) {
        Insight insight = analyze(caseId);
        Case toUpdate = new Case(
            Id = caseId,
            AI_Summary__c = insight.summary,
            AI_Recommended_Priority__c = insight.recommendedPriority,
            AI_Recommended_Action__c = truncate(insight.recommendedAction, 255),
            Sentiment__c = insight.sentiment
        );
        try {
            Database.update(toUpdate, AccessLevel.USER_MODE);
        } catch (Exception e) {
            AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_SUMMARY, SupportConstants.OUTCOME_FAILED, SupportConstants.SOURCE_RULES);
            entry.errorMessage = e.getTypeName();
            AIInteractionLogService.log(entry);
            throw new SupportException('The summary could not be saved. You may not have permission to edit this case.');
        }
        AIInteractionLogService.LogEntry ok = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_SUMMARY, SupportConstants.OUTCOME_SUCCESS, SupportConstants.SOURCE_RULES);
        ok.requestCategory = insight.issueCategory;
        ok.suggestedPriority = insight.recommendedPriority;
        ok.sentiment = insight.sentiment;
        ok.recommendedAction = insight.recommendedAction;
        ok.handoffRequired = insight.humanHandoffRequired;
        AIInteractionLogService.log(ok);
        return insight;
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    /** Builds the short, PII-scrubbed baseline summary stored in AI_Summary__c. */
    public static String buildSummary(String subject, String description, CaseRoutingRules.Decision d) {
        String safeSubject = AIInteractionLogService.sanitize(subject, 255);
        String snippet = AIInteractionLogService.sanitize(description, 240);
        String text = d.category + ' issue, ' + d.sentiment.toLowerCase() + ' sentiment: '
            + (safeSubject == null ? 'no subject provided' : safeSubject) + '.';
        if (snippet != null) {
            text += ' Customer reports: ' + snippet;
        }
        return truncate(text, 4000);
    }

    private static CaseRoutingRules.Input inputFor(Case c, Boolean premium, Integer threshold) {
        CaseRoutingRules.Input input = new CaseRoutingRules.Input();
        input.subject = c.Subject;
        input.description = c.Description;
        input.failedAttempts = c.AI_Failed_Attempts__c == null ? 0 : c.AI_Failed_Attempts__c.intValue();
        input.failedAttemptThreshold = threshold;
        input.premiumAccount = premium;
        return input;
    }

    private static Insight toInsight(Case c, CaseRoutingRules.Decision d) {
        Insight i = new Insight();
        i.caseId = c.Id;
        i.caseNumber = c.CaseNumber;
        i.subject = c.Subject;
        i.status = c.Status;
        i.priority = c.Priority;
        i.issueCategory = d.category;
        i.sentiment = d.sentiment;
        i.summary = buildSummary(c.Subject, c.Description, d);
        i.recommendedPriority = d.recommendedPriority;
        i.recommendedAction = d.suggestedAction;
        String queueKey = d.mustEscalate() ? d.escalationRouteKey : d.routeKey;
        String queueName = QueueRoutingService.queueDeveloperName(queueKey);
        i.recommendedQueue = String.isBlank(queueName) ? 'No queue mapping configured' : queueName;
        i.humanHandoffRequired = c.Human_Handoff_Required__c == true || d.mustEscalate();
        i.escalationRecommended = d.mustEscalate();
        i.escalationReason = String.isNotBlank(c.Escalation_Reason__c) ? c.Escalation_Reason__c : d.escalationReason;
        i.explanation = d.explanation;
        i.failedAttempts = c.AI_Failed_Attempts__c == null ? 0 : c.AI_Failed_Attempts__c.intValue();
        i.troubleshootingSteps = d.troubleshootingSteps;
        return i;
    }

    private static Case loadCase(Id caseId) {
        if (caseId == null) {
            throw new SupportException('A case Id is required.');
        }
        try {
            List<Case> rows = [
                SELECT Id, CaseNumber, Subject, Description, Status, Priority, AccountId,
                       AI_Failed_Attempts__c, Human_Handoff_Required__c, Escalation_Reason__c
                FROM Case
                WHERE Id = :caseId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                return rows[0];
            }
        } catch (QueryException e) {
            // Missing object or field permission: same answer as "not found" so nothing is leaked.
        }
        throw new SupportException('Case not found or you do not have access to it.');
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
