/** Agent / Flow action: classify a case with the deterministic rules and return recommendations (no data is changed). */
public with sharing class AgentActionClassifyCase {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the case to classify (15 or 18 characters).' required=true)
        public String caseId;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Issue Category') public String issueCategory;
        @InvocableVariable(label='Sentiment') public String sentiment;
        @InvocableVariable(label='Recommended Priority') public String recommendedPriority;
        @InvocableVariable(label='Recommended Action') public String recommendedAction;
        @InvocableVariable(label='Recommended Queue') public String recommendedQueue;
        @InvocableVariable(label='Escalation Recommended') public Boolean escalationRecommended;
        @InvocableVariable(label='Escalation Reason') public String escalationReason;
        @InvocableVariable(label='Explanation') public String explanation;
    }

    @InvocableMethod(label='SmartSupport: Classify Case' description='Returns the issue category, sentiment, recommended priority, queue and escalation recommendation for a case the user can access. Does not modify the case.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            AgentforceActionService.InsightOutcome outcome = AgentforceActionService.classify(req == null ? null : req.caseId);
            Response res = new Response();
            res.success = outcome.success;
            res.message = outcome.message;
            if (outcome.insight != null) {
                res.issueCategory = outcome.insight.issueCategory;
                res.sentiment = outcome.insight.sentiment;
                res.recommendedPriority = outcome.insight.recommendedPriority;
                res.recommendedAction = outcome.insight.recommendedAction;
                res.recommendedQueue = outcome.insight.recommendedQueue;
                res.escalationRecommended = outcome.insight.escalationRecommended;
                res.escalationReason = outcome.insight.escalationReason;
                res.explanation = outcome.insight.explanation;
            }
            responses.add(res);
        }
        return responses;
    }
}
