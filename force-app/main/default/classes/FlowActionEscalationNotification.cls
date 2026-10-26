/** Flow B action: sends the escalation notification once and reports whether it was really sent. */
public with sharing class FlowActionEscalationNotification {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the escalated case.' required=true)
        public Id caseId;
    }

    public class Response {
        @InvocableVariable(label='Sent' description='True only when the notification was actually sent.')
        public Boolean sent;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='SmartSupport: Notify Escalation' description='Sends one custom notification to the case owner or queue members. Skips cases that were already notified.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        List<Id> ids = new List<Id>();
        for (Request req : requests) {
            ids.add(req == null ? null : req.caseId);
        }
        Map<Id, SupportEscalationService.NotificationResult> byCase = new Map<Id, SupportEscalationService.NotificationResult>();
        List<Id> nonNull = new List<Id>();
        for (Id i : ids) {
            if (i != null) {
                nonNull.add(i);
            }
        }
        for (SupportEscalationService.NotificationResult nr : SupportEscalationService.notifyEscalations(nonNull)) {
            byCase.put(nr.caseId, nr);
        }
        for (Id i : ids) {
            Response res = new Response();
            SupportEscalationService.NotificationResult nr = i == null ? null : byCase.get(i);
            res.sent = nr != null && nr.sent;
            res.message = nr == null ? 'No case Id supplied.' : nr.message;
            responses.add(res);
        }
        return responses;
    }
}
