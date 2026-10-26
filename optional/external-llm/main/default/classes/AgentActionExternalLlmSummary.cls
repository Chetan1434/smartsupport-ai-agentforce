/**
 * OPTIONAL MODULE. Agent / Flow action that asks the external LLM for a validated suggestion for a case the user can
 * access. It returns the suggestion only: nothing is saved and nothing on the case is changed.
 */
public with sharing class AgentActionExternalLlmSummary {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the case to analyse (15 or 18 characters).' required=true)
        public String caseId;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Status' description='OK, DISABLED, INVALID_INPUT, RATE_LIMITED, HTTP_ERROR, NETWORK_ERROR, MALFORMED_RESPONSE or REJECTED_OUTPUT') public String status;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Issue Category') public String issueCategory;
        @InvocableVariable(label='Sentiment') public String sentiment;
        @InvocableVariable(label='Recommended Priority') public String recommendedPriority;
        @InvocableVariable(label='Recommended Action') public String recommendedAction;
        @InvocableVariable(label='Human Review Required') public Boolean humanReviewRequired;
        @InvocableVariable(label='Reason') public String reason;
    }

    @InvocableMethod(label='SmartSupport: External LLM Suggestion (optional)' description='Optional module. Sends a minimised, PII-scrubbed copy of the case text to the configured external LLM and returns a validated suggestion. Does not modify the case.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            responses.add(handle(req));
        }
        return responses;
    }

    private static Response handle(Request req) {
        Response res = new Response();
        res.humanReviewRequired = true;
        Id caseId = AgentforceActionService.toId(req == null ? null : req.caseId);
        if (caseId == null) {
            res.success = false;
            res.status = 'INVALID_INPUT';
            res.message = 'A valid case Id is required.';
            return res;
        }
        List<Case> rows;
        try {
            rows = [SELECT Id, Subject, Description FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1];
        } catch (QueryException e) {
            rows = new List<Case>();
        }
        if (rows.isEmpty()) {
            res.success = false;
            res.status = 'INVALID_INPUT';
            res.message = 'Case not found or you do not have access to it.';
            return res;
        }

        ExternalLLMService.LlmResult result = ExternalLLMService.summarize(rows[0].Subject, rows[0].Description);
        res.success = result.isOk();
        res.status = result.status.name();
        res.message = result.message;
        res.summary = result.caseSummary;
        res.issueCategory = result.issueCategory;
        res.sentiment = result.sentiment;
        res.recommendedPriority = result.recommendedPriority;
        res.recommendedAction = result.recommendedAction;
        res.humanReviewRequired = result.requiresHumanReview;
        res.reason = result.reason;

        AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(
            caseId, SupportConstants.TYPE_SUMMARY, result.isOk() ? SupportConstants.OUTCOME_SUCCESS : SupportConstants.OUTCOME_FAILED, SupportConstants.SOURCE_LLM
        );
        entry.requestCategory = result.issueCategory;
        entry.suggestedPriority = result.recommendedPriority;
        entry.sentiment = result.sentiment;
        entry.recommendedAction = result.recommendedAction;
        entry.handoffRequired = result.requiresHumanReview;
        entry.errorMessage = result.isOk() ? null : result.status.name();
        AIInteractionLogService.log(entry);
        return res;
    }
}
