/** Agent action: retrieve the status of a case. Requires the verified contact e-mail; a case number alone is never enough. */
public with sharing class AgentActionGetCaseStatus {

    public class Request {
        @InvocableVariable(label='Case Number' description='The case number the customer quotes, for example 00001026.' required=true)
        public String caseNumber;
        @InvocableVariable(label='Verified Contact Email' description='E-mail address of the customer, already verified by the agent verification step. Must match the contact on the case.' required=true)
        public String verifiedContactEmail;
    }

    public class Response {
        @InvocableVariable(label='Found') public Boolean found;
        @InvocableVariable(label='Case Id') public String caseId;
        @InvocableVariable(label='Case Number') public String caseNumber;
        @InvocableVariable(label='Subject') public String subject;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Priority') public String priority;
        @InvocableVariable(label='Human Handoff Required') public Boolean humanHandoffRequired;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='SmartSupport: Get Case Status' description='Returns minimal status information for a case the running user can access and whose contact e-mail matches the verified e-mail.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            CaseActionService.StatusResult result = AgentforceActionService.getCaseStatus(
                req == null ? null : req.caseNumber,
                req == null ? null : req.verifiedContactEmail
            );
            Response res = new Response();
            res.found = result.found;
            res.caseId = result.caseId == null ? null : String.valueOf(result.caseId);
            res.caseNumber = result.caseNumber;
            res.subject = result.subject;
            res.status = result.status;
            res.priority = result.priority;
            res.humanHandoffRequired = result.humanHandoffRequired;
            res.message = result.message;
            responses.add(res);
        }
        return responses;
    }
}
