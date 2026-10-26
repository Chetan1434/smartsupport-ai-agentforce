/**
 * Shared logic behind every SmartSupport Agentforce / Flow action.
 *
 * Apex allows only ONE @InvocableMethod per class, so each action is a thin AgentAction* class that maps its
 * request to a method here. All validation, permission handling and audit logging is in this class and in the
 * services it calls, so the LWC controller and the agent behave identically.
 *
 * Security model: actions run as the user (or agent user) executing them, in USER mode, so object permissions,
 * field-level security and record sharing always apply. No action accepts SOQL, field lists or free-form SObjects.
 */
public with sharing class AgentforceActionService {

    public class InsightOutcome {
        public Boolean success = false;
        public String message;
        public CaseIntelligenceService.Insight insight;
    }

    /** Converts agent-supplied text into an Id; returns null for anything that is not a valid 15/18 character Id. */
    public static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.length() != 15 && trimmed.length() != 18) {
            return null;
        }
        try {
            return Id.valueOf(trimmed);
        } catch (Exception e) {
            return null;
        }
    }

    /** Knowledge search for the agent. Logs the outcome and counts an unsuccessful search as a failed attempt. */
    public static KnowledgeSearchService.SearchResult searchKnowledge(String question, String caseIdText) {
        KnowledgeSearchService.SearchResult result = KnowledgeSearchService.search(question);
        Id caseId = toId(caseIdText);

        String outcome = SupportConstants.OUTCOME_SUCCESS;
        if (result.status == SupportConstants.KB_INSUFFICIENT) {
            outcome = SupportConstants.OUTCOME_INSUFFICIENT;
        } else if (result.status != SupportConstants.KB_FOUND) {
            outcome = SupportConstants.OUTCOME_FAILED;
        }
        AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_KNOWLEDGE, outcome, SupportConstants.SOURCE_AGENTFORCE);
        entry.handoffRequired = result.humanRecommended;
        entry.errorMessage = result.status == SupportConstants.KB_FOUND ? null : result.status;
        AIInteractionLogService.log(entry);

        if (caseId != null && result.status == SupportConstants.KB_INSUFFICIENT) {
            SupportEscalationService.recordFailedAttempt(caseId);
        }
        return result;
    }

    public static InsightOutcome classify(String caseIdText) {
        InsightOutcome outcome = new InsightOutcome();
        Id caseId = toId(caseIdText);
        if (caseId == null) {
            outcome.message = 'A valid case Id is required.';
            return outcome;
        }
        try {
            outcome.insight = CaseIntelligenceService.analyze(caseId);
            outcome.success = true;
            outcome.message = 'Case classified.';
            AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_CLASSIFICATION, SupportConstants.OUTCOME_SUCCESS, SupportConstants.SOURCE_AGENTFORCE);
            entry.requestCategory = outcome.insight.issueCategory;
            entry.suggestedPriority = outcome.insight.recommendedPriority;
            entry.sentiment = outcome.insight.sentiment;
            entry.recommendedAction = outcome.insight.recommendedAction;
            entry.handoffRequired = outcome.insight.humanHandoffRequired;
            AIInteractionLogService.log(entry);
        } catch (SupportException e) {
            outcome.message = e.getMessage();
        }
        return outcome;
    }

    public static InsightOutcome summarize(String caseIdText) {
        InsightOutcome outcome = new InsightOutcome();
        Id caseId = toId(caseIdText);
        if (caseId == null) {
            outcome.message = 'A valid case Id is required.';
            return outcome;
        }
        try {
            outcome.insight = CaseIntelligenceService.summarizeAndSave(caseId);
            outcome.success = true;
            outcome.message = 'Case summarized.';
        } catch (SupportException e) {
            outcome.message = e.getMessage();
        }
        return outcome;
    }

    /** Agent status lookup: ALWAYS requires the verified contact e-mail (the agent user may see many cases). */
    public static CaseActionService.StatusResult getCaseStatus(String caseNumber, String verifiedEmail) {
        return CaseActionService.getCaseStatus(caseNumber, verifiedEmail, true, SupportConstants.SOURCE_AGENTFORCE);
    }

    public static CaseActionService.ActionResult createCase(String subject, String description, String priority, String contactIdText) {
        Id contactId = toId(contactIdText);
        if (String.isNotBlank(contactIdText) && contactId == null) {
            CaseActionService.ActionResult invalid = new CaseActionService.ActionResult();
            invalid.message = 'The contact Id is not valid.';
            return invalid;
        }
        return CaseActionService.createCase(subject, description, priority, contactId, SupportConstants.SOURCE_AGENTFORCE);
    }

    public static CaseActionService.ActionResult addComment(String caseIdText, String comment) {
        Id caseId = toId(caseIdText);
        if (caseId == null) {
            CaseActionService.ActionResult invalid = new CaseActionService.ActionResult();
            invalid.message = 'A valid case Id is required.';
            return invalid;
        }
        // Agent comments are internal (not published to the customer) so a human can review them first.
        return CaseActionService.addComment(caseId, comment, false, SupportConstants.SOURCE_AGENTFORCE);
    }

    public static SupportEscalationService.EscalationResult escalate(String caseIdText, String reason) {
        Id caseId = toId(caseIdText);
        if (caseId == null) {
            SupportEscalationService.EscalationResult invalid = new SupportEscalationService.EscalationResult();
            invalid.message = 'A valid case Id is required.';
            return invalid;
        }
        return SupportEscalationService.escalate(caseId, reason, SupportConstants.SOURCE_AGENTFORCE);
    }
}
