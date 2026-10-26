/** Tests for the two Flow-facing invocable actions (Flow A intake, Flow B notification). */
@IsTest
private class FlowActionsTest {

    @IsTest
    static void intakeActionProcessesAnUnprocessedCaseExactlyOnce() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            CaseTriggerHandler.bypass = true; // simulate a case created while the trigger automation was not active
            Case c = SupportTestDataFactory.createCase('Invoice problem', 'Wrong amount charged.');
            CaseTriggerHandler.bypass = false;
            Assert.isFalse(SupportTestDataFactory.reload(c.Id).Intake_Processed__c);

            FlowActionCaseIntake.Request req = new FlowActionCaseIntake.Request();
            req.caseId = c.Id;
            FlowActionCaseIntake.Response first = FlowActionCaseIntake.run(new List<FlowActionCaseIntake.Request>{ req })[0];
            Assert.isTrue(first.processed, first.message);

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.CAT_BILLING, saved.Issue_Category__c);
            Assert.isTrue(saved.Intake_Processed__c);

            FlowActionCaseIntake.Response second = FlowActionCaseIntake.run(new List<FlowActionCaseIntake.Request>{ req })[0];
            Assert.isFalse(second.processed, 'A processed case is never processed again.');
            Assert.isTrue(second.message.contains('Nothing to do'));
    
        }
    }

    @IsTest
    static void intakeActionHandlesBulkAndInvalidRequests() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseTriggerHandler.bypass = true;
            List<Case> cases = new List<Case>();
            for (Integer i = 0; i < 20; i++) {
                cases.add(SupportTestDataFactory.buildCase('Invoice ' + i, 'billing question'));
            }
            insert cases;
            CaseTriggerHandler.bypass = false;

            List<FlowActionCaseIntake.Request> requests = new List<FlowActionCaseIntake.Request>();
            for (Case c : cases) {
                FlowActionCaseIntake.Request r = new FlowActionCaseIntake.Request();
                r.caseId = c.Id;
                requests.add(r);
            }
            requests.add(new FlowActionCaseIntake.Request()); // no case Id
            requests.add(null);

            List<FlowActionCaseIntake.Response> responses = FlowActionCaseIntake.run(requests);
            Assert.areEqual(22, responses.size());
            Assert.isTrue(responses[0].processed);
            Assert.isFalse(responses[20].processed);
            Assert.isFalse(responses[21].processed);
            Assert.areEqual(20, [SELECT COUNT() FROM Case WHERE Intake_Processed__c = true AND Issue_Category__c = :SupportConstants.CAT_BILLING]);
            Assert.isTrue(FlowActionCaseIntake.run(null).isEmpty());
            Assert.isTrue(FlowActionCaseIntake.run(new List<FlowActionCaseIntake.Request>()).isEmpty());
    
        }
    }

    @IsTest
    static void notificationActionNeverReportsSentForAnAlreadyNotifiedCase() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Need help', 'I want to talk to a human.');
            update new Case(Id = c.Id, Escalation_Notified__c = true);

            FlowActionEscalationNotification.Request req = new FlowActionEscalationNotification.Request();
            req.caseId = c.Id;
            FlowActionEscalationNotification.Response res = FlowActionEscalationNotification.run(new List<FlowActionEscalationNotification.Request>{ req })[0];
            Assert.isFalse(res.sent, 'The Flow must never be told a duplicate notification was sent.');
            Assert.isTrue(res.message.contains('Already notified'));
    
        }
    }

    @IsTest
    static void notificationActionHandlesMissingIdsAndEmptyInput() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isTrue(FlowActionEscalationNotification.run(null).isEmpty());
            Assert.isTrue(FlowActionEscalationNotification.run(new List<FlowActionEscalationNotification.Request>()).isEmpty());

            List<FlowActionEscalationNotification.Response> responses = FlowActionEscalationNotification.run(
                new List<FlowActionEscalationNotification.Request>{ new FlowActionEscalationNotification.Request(), null }
            );
            Assert.areEqual(2, responses.size());
            Assert.isFalse(responses[0].sent);
            Assert.isFalse(responses[1].sent);
            Assert.areEqual('No case Id supplied.', responses[0].message);
    
        }
    }
}
