/** Agent action: add an INTERNAL comment to a case the running user can access. */
public with sharing class AgentActionAddComment {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the case (15 or 18 characters).' required=true)
        public String caseId;
        @InvocableVariable(label='Comment' description='Comment text (max 4000 characters).' required=true)
        public String comment;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='SmartSupport: Add Case Comment' description='Adds an internal (unpublished) comment to a case the running user can access.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }
        for (Request req : requests) {
            CaseActionService.ActionResult result = AgentforceActionService.addComment(
                req == null ? null : req.caseId,
                req == null ? null : req.comment
            );
            Response res = new Response();
            res.success = result.success;
            res.message = result.message;
            responses.add(res);
        }
        return responses;
    }
}
