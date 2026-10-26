@IsTest
private class SupportEscalationServiceTest {

    private static Integer escalationLogs(Id caseId) {
        return [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :caseId AND Interaction_Type__c = :SupportConstants.TYPE_ESCALATION];
    }

    @IsTest
    static void manualEscalationFlagsRoutesAndLogsOnce() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Question', 'How do I export a report?');

            SupportEscalationService.EscalationResult result = SupportEscalationService.escalate(c.Id, null);
            Assert.isTrue(result.success, result.message);
            Assert.isFalse(result.alreadyEscalated);
            Assert.areEqual(SupportConstants.REASON_MANUAL, result.reason);

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Human_Handoff_Required__c);
            Assert.isTrue(saved.IsEscalated);
            Assert.isFalse(saved.Escalation_Notified__c);
            Assert.areEqual(SupportConstants.REASON_MANUAL, saved.Escalation_Reason__c);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_GENERAL), saved.OwnerId);
            Assert.areEqual(1, escalationLogs(c.Id), 'One audit entry: the trigger must not add a duplicate.');
            Assert.areEqual(SupportConstants.SOURCE_UI, [SELECT Source__c FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_ESCALATION].Source__c);
    
        }
    }

    @IsTest
    static void securityAndOutageEscalationsRaisePriorityAndUseSpecialQueues() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Case security = SupportTestDataFactory.createCase('Odd emails', 'Question about some odd emails');
            Case outage = SupportTestDataFactory.createCase('Slow system', 'Everything feels slow today');

            Assert.isTrue(SupportEscalationService.escalate(security.Id, SupportConstants.REASON_SECURITY).success);
            Assert.isTrue(SupportEscalationService.escalate(outage.Id, SupportConstants.REASON_OUTAGE).success);

            Case s = SupportTestDataFactory.reload(security.Id);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, s.Priority);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_SECURITY), s.OwnerId);
            Case o = SupportTestDataFactory.reload(outage.Id);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, o.Priority);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_URGENT), o.OwnerId);
    
        }
    }

    @IsTest
    static void escalationIsIdempotentAndCreatesNoSecondNotificationOrLog() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Question', 'How do I export a report?');
            SupportEscalationService.escalate(c.Id, SupportConstants.REASON_MANUAL);
            update new Case(Id = c.Id, Escalation_Notified__c = true); // the Flow already notified

            SupportEscalationService.EscalationResult second = SupportEscalationService.escalate(c.Id, SupportConstants.REASON_SECURITY);
            Assert.isTrue(second.success);
            Assert.isTrue(second.alreadyEscalated);

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Escalation_Notified__c, 'The notified flag must not be reset by a repeated escalation.');
            Assert.areEqual(SupportConstants.REASON_MANUAL, saved.Escalation_Reason__c, 'The first reason is kept.');
            Assert.areEqual(1, escalationLogs(c.Id));
    
        }
    }

    @IsTest
    static void invalidInputIsRejectedWithClearMessages() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isFalse(SupportEscalationService.escalate(null, SupportConstants.REASON_MANUAL).success);
            Case c = SupportTestDataFactory.createCase('Question', 'x');
            SupportEscalationService.EscalationResult bad = SupportEscalationService.escalate(c.Id, 'Because I said so');
            Assert.isFalse(bad.success);
            Assert.isTrue(bad.message.contains('Unsupported escalation reason'));
            Assert.isFalse(SupportTestDataFactory.reload(c.Id).Human_Handoff_Required__c, 'Nothing may change for an invalid request.');
    
        }
    }

    @IsTest
    static void unknownCaseIsBlockedAndAudited() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Question', 'x');
            delete c;
            SupportEscalationService.EscalationResult result = SupportEscalationService.escalate(c.Id, SupportConstants.REASON_MANUAL);
            Assert.isFalse(result.success);
            Assert.isTrue(result.message.contains('not found or you do not have access'));
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Outcome__c = :SupportConstants.OUTCOME_BLOCKED AND Interaction_Type__c = :SupportConstants.TYPE_ESCALATION]);
    
        }
    }

    @IsTest
    static void userWithoutCaseAccessCannotEscalate() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Question', 'x');
            User noAccess = SupportTestDataFactory.createNoAccessUser();
            if (noAccess == null) {
                return;
            }
            System.runAs(noAccess) {
                Assert.isFalse(SupportEscalationService.escalate(c.Id, SupportConstants.REASON_MANUAL).success);
            }
            Assert.isFalse(SupportTestDataFactory.reload(c.Id).Human_Handoff_Required__c);
    
        }
    }

    @IsTest
    static void escalationWorksWithoutQueueMapping() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            QueueRoutingService.mappingOverride = new Map<String, String>();
            Case c = SupportTestDataFactory.createCase('Question', 'x');
            Assert.isTrue(SupportEscalationService.escalate(c.Id, SupportConstants.REASON_MANUAL).success);
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Human_Handoff_Required__c);
            Assert.areEqual(UserInfo.getUserId(), saved.OwnerId, 'No valid queue: the owner stays unchanged.');
    
        }
    }

    @IsTest
    static void requestHumanUsesTheCustomerRequestedReason() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Question', 'x');
            SupportEscalationService.EscalationResult result = SupportEscalationService.requestHuman(c.Id, SupportConstants.SOURCE_AGENTFORCE);
            Assert.isTrue(result.success);
            Assert.areEqual(SupportConstants.REASON_HUMAN, SupportTestDataFactory.reload(c.Id).Escalation_Reason__c);
            Assert.areEqual(SupportConstants.SOURCE_AGENTFORCE, [SELECT Source__c FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_ESCALATION].Source__c);
    
        }
    }

    @IsTest
    static void repeatedFailedAttemptsTriggerHandoffAtTheThreshold() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Question about my order', 'Just checking something.');
            Integer threshold = SupportConstants.failedAttemptThreshold();

            for (Integer i = 1; i < threshold; i++) {
                Assert.areEqual(i, SupportEscalationService.recordFailedAttempt(c.Id));
                Assert.isFalse(SupportTestDataFactory.reload(c.Id).Human_Handoff_Required__c, 'Below the threshold there is no handoff.');
            }
            Assert.areEqual(threshold, SupportEscalationService.recordFailedAttempt(c.Id));

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Human_Handoff_Required__c, 'Reaching the threshold must hand the case to a human.');
            Assert.areEqual(SupportConstants.REASON_AI_FAILURE, saved.Escalation_Reason__c);
            Assert.areEqual(1, escalationLogs(c.Id));
    
        }
    }

    @IsTest
    static void recordFailedAttemptHandlesNullAndUnknownCase() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isNull(SupportEscalationService.recordFailedAttempt(null));
            Case c = SupportTestDataFactory.createCase('x', 'y');
            delete c;
            Assert.isNull(SupportEscalationService.recordFailedAttempt(c.Id));
    
        }
    }

    @IsTest
    static void notificationIsSkippedWhenAlreadyNotified() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Need help', 'I want to talk to a human.');
            update new Case(Id = c.Id, Escalation_Notified__c = true);

            List<SupportEscalationService.NotificationResult> results = SupportEscalationService.notifyEscalations(new List<Id>{ c.Id });
            Assert.areEqual(1, results.size());
            Assert.isFalse(results[0].sent, 'No duplicate notification may be sent.');
            Assert.isTrue(results[0].message.contains('Already notified'));
    
        }
    }

    @IsTest
    static void notificationHandlesUnknownCasesAndEmptyInput() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isTrue(SupportEscalationService.notifyEscalations(null).isEmpty());
            Assert.isTrue(SupportEscalationService.notifyEscalations(new List<Id>()).isEmpty());
            Case c = SupportTestDataFactory.createCase('x', 'y');
            delete c;
            List<SupportEscalationService.NotificationResult> results = SupportEscalationService.notifyEscalations(new List<Id>{ c.Id });
            Assert.isFalse(results[0].sent);
            Assert.areEqual('Case not found.', results[0].message);
    
        }
    }

    @IsTest
    static void notificationForEscalatedCaseReportsOutcomeHonestly() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Need help', 'I want to talk to a human.');
            List<SupportEscalationService.NotificationResult> results = SupportEscalationService.notifyEscalations(new List<Id>{ c.Id });
            Assert.areEqual(1, results.size());
            Assert.areEqual(c.Id, results[0].caseId);
            Assert.isNotNull(results[0].message);
            // Whether the platform delivers the notification in a test context depends on the org (type deployed, recipients).
            // The contract that matters: sent == true only together with a "sent" message.
            Assert.areEqual(results[0].sent, results[0].message.startsWith('Notification sent'));
    
        }
    }
}
