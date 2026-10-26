/** Agent action: escalate a case / hand it to a human. Idempotent; never creates a second notification. */
public with sharing class AgentActionEscalateCase {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the case to escalate (15 or 18 characters).' required=true)
        public String caseId;
        @InvocableVariable(label='Reason' description='One of: Security Concern, Widespread Outage, Customer Requested Human, Repeated AI Failure, Insufficient Knowledge, Premium Account High Priority, Manual Escalation. Empty means Manual Escalation.')
        public String reason;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Already Escalated') public Boolean alreadyEscalated;
        @InvocableVariable(label='Reason') public String reason;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='SmartSupport: Escalate Case' description='Flags a case for human handoff, raises priority for security/outage reasons and routes it to the configured queue. A case that is already escalated is not changed again.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            SupportEscalationService.EscalationResult result = AgentforceActionService.escalate(
                req == null ? null : req.caseId,
                req == null ? null : req.reason
            );
            Response res = new Response();
            res.success = result.success;
            res.alreadyEscalated = result.alreadyEscalated;
            res.reason = result.reason;
            res.message = result.message;
            responses.add(res);
        }
        return responses;
    }
}
