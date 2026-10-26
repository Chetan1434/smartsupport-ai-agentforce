/** Agent / Flow action: create a support case. The Case trigger classifies and routes it automatically. */
public with sharing class AgentActionCreateCase {

    public class Request {
        @InvocableVariable(label='Subject' description='Short subject of the problem (max 255 characters).' required=true)
        public String subject;
        @InvocableVariable(label='Description' description='Details of the problem in the customer words. Do not include passwords or card numbers.')
        public String description;
        @InvocableVariable(label='Priority' description='Optional: High, Medium or Low. Leave empty to let the rules decide.')
        public String priority;
        @InvocableVariable(label='Contact Id' description='Optional: Id of the verified contact the case belongs to.')
        public String contactId;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Case Id') public String caseId;
        @InvocableVariable(label='Case Number') public String caseNumber;
        @InvocableVariable(label='Issue Category') public String issueCategory;
        @InvocableVariable(label='Human Handoff Required') public Boolean humanHandoffRequired;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='SmartSupport: Create Case' description='Creates a support case for the running user. The case is classified, prioritized and routed by the SmartSupport rules.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            CaseActionService.ActionResult result = AgentforceActionService.createCase(
                req == null ? null : req.subject,
                req == null ? null : req.description,
                req == null ? null : req.priority,
                req == null ? null : req.contactId
            );
            Response res = new Response();
            res.success = result.success;
            res.caseId = result.caseId == null ? null : String.valueOf(result.caseId);
            res.caseNumber = result.caseNumber;
            res.issueCategory = result.issueCategory;
            res.humanHandoffRequired = result.humanHandoffRequired;
            res.message = result.message;
            responses.add(res);
        }
        return responses;
    }
}
