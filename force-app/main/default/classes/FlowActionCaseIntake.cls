/**
 * Flow A support action. Runs the SAME intake logic as the Case trigger (CaseIntelligenceService.applyIntake)
 * for cases that were created while the trigger automation was not active (Intake_Processed__c = false).
 * It is a no-op when the trigger already processed the case or when the automation kill switch is off, so the
 * trigger and the Flow can never process the same case twice.
 */
public with sharing class FlowActionCaseIntake {

    public class Request {
        @InvocableVariable(label='Case Id' description='Id of the newly created case.' required=true)
        public Id caseId;
    }

    public class Response {
        @InvocableVariable(label='Processed') public Boolean processed;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='SmartSupport: Run Case Intake' description='Classifies, prioritizes and routes a case that has not been processed yet. Does nothing for cases already processed.' category='SmartSupport')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        Set<Id> ids = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.caseId != null) {
                ids.add(req.caseId);
            }
        }

        Set<Id> processedIds = new Set<Id>();
        String failure = null;
        if (SupportConstants.isCaseAutomationEnabled() && !ids.isEmpty()) {
            try {
                List<Case> cases = [
                    SELECT Id, Subject, Description, AccountId, OwnerId, Priority, Intake_Processed__c,
                           Human_Handoff_Required__c, Escalation_Reason__c, Escalation_Notified__c,
                           AI_Failed_Attempts__c, IsEscalated
                    FROM Case
                    WHERE Id IN :ids AND Intake_Processed__c = false
                    WITH USER_MODE
                ];
                if (!cases.isEmpty()) {
                    CaseIntelligenceService.applyIntake(cases, null);
                    Database.update(cases, AccessLevel.USER_MODE);
                    for (Case c : cases) {
                        processedIds.add(c.Id);
                    }
                }
            } catch (Exception e) {
                failure = 'Intake could not be completed: ' + e.getTypeName();
            }
        }

        for (Request req : requests) {
            Response res = new Response();
            Boolean done = req != null && req.caseId != null && processedIds.contains(req.caseId);
            res.processed = done;
            res.message = failure != null ? failure : (done ? 'Case processed.' : 'Nothing to do (already processed or automation disabled).');
            responses.add(res);
        }
        return responses;
    }
}
