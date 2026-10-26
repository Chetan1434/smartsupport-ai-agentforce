/**
 * Server side of caseIntelligencePanel, knowledgeAssistant and caseActionPanel.
 * A thin layer: it only converts service results into UI results. No business logic lives here and no
 * credentials or privileged operations are exposed to JavaScript.
 */
public with sharing class SupportAssistantController {

    @AuraEnabled
    public static CaseIntelligenceService.Insight getInsight(Id caseId) {
        try {
            return CaseIntelligenceService.analyze(caseId);
        } catch (SupportException e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static CaseIntelligenceService.Insight saveSummary(Id caseId) {
        try {
            return CaseIntelligenceService.summarizeAndSave(caseId);
        } catch (SupportException e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static KnowledgeSearchService.SearchResult searchKnowledge(String question, Id caseId) {
        KnowledgeSearchService.SearchResult result = KnowledgeSearchService.search(question);
        String outcome = SupportConstants.OUTCOME_SUCCESS;
        if (result.status == SupportConstants.KB_INSUFFICIENT) {
            outcome = SupportConstants.OUTCOME_INSUFFICIENT;
        } else if (result.status != SupportConstants.KB_FOUND) {
            outcome = SupportConstants.OUTCOME_FAILED;
        }
        AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_KNOWLEDGE, outcome, SupportConstants.SOURCE_UI);
        entry.handoffRequired = result.humanRecommended;
        entry.errorMessage = result.status == SupportConstants.KB_FOUND ? null : result.status;
        AIInteractionLogService.log(entry);
        return result;
    }

    @AuraEnabled
    public static CaseActionService.ActionResult createCase(String subject, String description, String priority) {
        return CaseActionService.createCase(subject, description, priority, null, SupportConstants.SOURCE_UI);
    }

    /**
     * Internal (Standard) users are authorised by record sharing. Every other user type (Experience Cloud, guest)
     * must additionally supply the e-mail address of the case contact.
     */
    @AuraEnabled
    public static CaseActionService.StatusResult getCaseStatus(String caseNumber, String contactEmail) {
        Boolean requireEmail = UserInfo.getUserType() != 'Standard';
        return CaseActionService.getCaseStatus(caseNumber, contactEmail, requireEmail, SupportConstants.SOURCE_UI);
    }

    @AuraEnabled
    public static CaseActionService.ActionResult addComment(Id caseId, String body, Boolean isPublic) {
        return CaseActionService.addComment(caseId, body, isPublic, SupportConstants.SOURCE_UI);
    }

    @AuraEnabled
    public static SupportEscalationService.EscalationResult escalateCase(Id caseId, String reason) {
        return SupportEscalationService.escalate(caseId, reason, SupportConstants.SOURCE_UI);
    }

    @AuraEnabled
    public static SupportEscalationService.EscalationResult requestHuman(Id caseId) {
        return SupportEscalationService.requestHuman(caseId, SupportConstants.SOURCE_UI);
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
