/** Agent / Flow action: summarize a case (rule-based baseline) and store the summary on the case. Used by Flow C. */
public with sharing class AgentActionSummarizeCase {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the case to summarize (15 or 18 characters).' required=true)
        public String caseId;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Recommended Action') public String recommendedAction;
        @InvocableVariable(label='Human Review Required') public Boolean humanReviewRequired;
    }

    @InvocableMethod(label='SmartSupport: Summarize Case' description='Creates a short summary and next-action recommendation for a case the user can access and saves them on the case.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            AgentforceActionService.InsightOutcome outcome = AgentforceActionService.summarize(req == null ? null : req.caseId);
            Response res = new Response();
            res.success = outcome.success;
            res.message = outcome.message;
            res.humanReviewRequired = true; // summaries are suggestions; a person must review before anything customer-facing is sent
            if (outcome.insight != null) {
                res.summary = outcome.insight.summary;
                res.recommendedAction = outcome.insight.recommendedAction;
                res.humanReviewRequired = outcome.insight.humanHandoffRequired;
            }
            responses.add(res);
        }
        return responses;
    }
}
