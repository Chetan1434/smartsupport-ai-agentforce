@IsTest
private class CaseTriggerHandlerTest {

    private static Integer logCount(Id caseId, String interactionType) {
        return [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :caseId AND Interaction_Type__c = :interactionType];
    }

    @IsTest
    static void singleBillingCaseIsClassifiedAndRoutedOnInsert() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Double charge on invoice', 'I was charged twice this month.');

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.CAT_BILLING, saved.Issue_Category__c);
            Assert.areEqual(SupportConstants.SENT_NEUTRAL, saved.Sentiment__c);
            Assert.areEqual(SupportConstants.PRIORITY_MEDIUM, saved.AI_Recommended_Priority__c);
            Assert.isTrue(saved.Intake_Processed__c, 'The intake guard flag must be set.');
            Assert.isFalse(saved.Human_Handoff_Required__c);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_BILLING), saved.OwnerId, 'The case must be routed to the mapped billing queue.');
            Assert.isTrue(saved.AI_Summary__c.contains('Billing'));
            Assert.isNotNull(saved.AI_Recommended_Action__c);
            Assert.areEqual(1, logCount(c.Id, SupportConstants.TYPE_CLASSIFICATION), 'Exactly one classification audit entry.');
            Assert.areEqual(0, logCount(c.Id, SupportConstants.TYPE_ESCALATION));
    
        }
    }

    @IsTest
    static void accountAccessCaseIsNotClassifiedAsGeneralTechnical() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Cannot sign in', 'My password does not work and I am locked out.');
            Assert.areEqual(SupportConstants.CAT_ACCESS, SupportTestDataFactory.reload(c.Id).Issue_Category__c);
    
        }
    }

    @IsTest
    static void outageCaseIsEscalatedRaisedToHighAndSentToUrgentQueue() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.buildCase('Service is down for all users', 'Nobody can log in to the platform.');
            c.Priority = SupportConstants.PRIORITY_LOW;
            insert c;

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, saved.Priority, 'Urgent-by-rule signals may raise the standard priority.');
            Assert.isTrue(saved.Human_Handoff_Required__c);
            Assert.isTrue(saved.IsEscalated);
            Assert.areEqual(SupportConstants.REASON_OUTAGE, saved.Escalation_Reason__c);
            Assert.isFalse(saved.Escalation_Notified__c, 'Notification has not been sent yet; the Flow sends it once.');
            Assert.areEqual(queues.get(SupportConstants.ROUTE_URGENT), saved.OwnerId);
            Assert.areEqual(1, logCount(c.Id, SupportConstants.TYPE_ESCALATION));
    
        }
    }

    @IsTest
    static void securityCaseFollowsSecurityPath() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Possible data breach', 'We see unauthorized access from an unknown location.');
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.CAT_SECURITY, saved.Issue_Category__c);
            Assert.areEqual(SupportConstants.REASON_SECURITY, saved.Escalation_Reason__c);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, saved.Priority);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_SECURITY), saved.OwnerId);
    
        }
    }

    @IsTest
    static void customerAskingForHumanGetsHandoffButPriorityIsUntouched() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.buildCase('Question about my plan', 'Please let me speak to a person.');
            c.Priority = SupportConstants.PRIORITY_LOW;
            insert c;
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Human_Handoff_Required__c);
            Assert.areEqual(SupportConstants.REASON_HUMAN, saved.Escalation_Reason__c);
            Assert.areEqual(SupportConstants.PRIORITY_LOW, saved.Priority, 'A human request must not change the priority.');
    
        }
    }

    @IsTest
    static void aiRecommendationNeverOverridesPriority() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.buildCase('Terrible billing error', 'I am furious about the invoice.');
            c.Priority = SupportConstants.PRIORITY_LOW;
            insert c;
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, saved.AI_Recommended_Priority__c);
            Assert.areEqual(SupportConstants.PRIORITY_LOW, saved.Priority, 'The recommendation is advisory; Priority stays as the user set it.');
    
        }
    }

    @IsTest
    static void missingQueueMappingLeavesOwnerUnchanged() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            QueueRoutingService.mappingOverride = new Map<String, String>{ SupportConstants.ROUTE_BILLING => 'No_Such_Queue_Anywhere' };
            Case c = SupportTestDataFactory.createCase('Invoice problem', 'Wrong amount charged.');
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.CAT_BILLING, saved.Issue_Category__c, 'Classification still works without a queue.');
            Assert.areEqual(UserInfo.getUserId(), saved.OwnerId, 'Without a valid queue the owner must be left alone.');
            Assert.isTrue(saved.Intake_Processed__c);
    
        }
    }

    @IsTest
    static void premiumAccountWithHighPriorityRecommendationIsEscalated() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Account premium = SupportTestDataFactory.createAccount('Premium Co', 'Premium');
            Account standard = SupportTestDataFactory.createAccount('Standard Co', 'Standard');
            Case p = SupportTestDataFactory.buildCase('Terrible billing error', 'I am furious about the invoice.');
            p.AccountId = premium.Id;
            Case s = SupportTestDataFactory.buildCase('Terrible billing error', 'I am furious about the invoice.');
            s.AccountId = standard.Id;
            insert new List<Case>{ p, s };

            Case premiumSaved = SupportTestDataFactory.reload(p.Id);
            Assert.isTrue(premiumSaved.Human_Handoff_Required__c);
            Assert.areEqual(SupportConstants.REASON_PREMIUM, premiumSaved.Escalation_Reason__c);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_URGENT), premiumSaved.OwnerId);
            Assert.isFalse(SupportTestDataFactory.reload(s.Id).Human_Handoff_Required__c, 'Standard accounts are not escalated by this rule.');
    
        }
    }

    @IsTest
    static void bulkInsertOf200CasesIsClassifiedCorrectlyAndWithinLimits() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            List<Case> cases = new List<Case>();
            for (Integer i = 0; i < 200; i++) {
                Integer kind = Math.mod(i, 4);
                if (kind == 0) {
                    cases.add(SupportTestDataFactory.buildCase('Invoice ' + i, 'Question about my invoice'));
                } else if (kind == 1) {
                    cases.add(SupportTestDataFactory.buildCase('Login ' + i, 'I forgot my password'));
                } else if (kind == 2) {
                    cases.add(SupportTestDataFactory.buildCase('Outage ' + i, 'Service is down for all users'));
                } else {
                    cases.add(SupportTestDataFactory.buildCase('Hello ' + i, 'Do you have a partner program?'));
                }
            }
            Test.startTest();
            insert cases;
            Integer queriesUsed = Limits.getQueries();
            Test.stopTest();

            Assert.isTrue(queriesUsed <= 10, 'Intake must be bulk safe (fixed number of queries), used ' + queriesUsed);
            Assert.areEqual(50, [SELECT COUNT() FROM Case WHERE Issue_Category__c = :SupportConstants.CAT_BILLING]);
            Assert.areEqual(50, [SELECT COUNT() FROM Case WHERE Issue_Category__c = :SupportConstants.CAT_ACCESS]);
            Assert.areEqual(50, [SELECT COUNT() FROM Case WHERE Issue_Category__c = :SupportConstants.CAT_TECHNICAL AND Human_Handoff_Required__c = true]);
            Assert.areEqual(50, [SELECT COUNT() FROM Case WHERE Issue_Category__c = :SupportConstants.CAT_GENERAL]);
            Assert.areEqual(200, [SELECT COUNT() FROM Case WHERE Intake_Processed__c = true]);
            Assert.areEqual(200, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Interaction_Type__c = :SupportConstants.TYPE_CLASSIFICATION]);
            Assert.areEqual(50, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Interaction_Type__c = :SupportConstants.TYPE_ESCALATION]);
    
        }
    }

    @IsTest
    static void updateWithoutRelevantChangeDoesNotReprocess() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Invoice problem', 'Wrong amount charged.');
            Integer logsBefore = [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id];

            // An agent corrects the category; this field is not an input of the rules, so it must survive.
            Case toUpdate = new Case(Id = c.Id, Issue_Category__c = SupportConstants.CAT_GENERAL, Priority = SupportConstants.PRIORITY_LOW);
            update toUpdate;

            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.CAT_GENERAL, saved.Issue_Category__c, 'The manual correction must not be overwritten.');
            Assert.areEqual(logsBefore, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id], 'No new audit rows for a non-relevant update.');
    
        }
    }

    @IsTest
    static void changingDescriptionReevaluatesAndEscalatesOnce() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Map<String, Id> queues = SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Question', 'How do I export a report?');
            Assert.isFalse(SupportTestDataFactory.reload(c.Id).Human_Handoff_Required__c);

            update new Case(Id = c.Id, Description = 'Service is down for all users since this morning');
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(SupportConstants.CAT_TECHNICAL, saved.Issue_Category__c);
            Assert.isTrue(saved.Human_Handoff_Required__c);
            Assert.areEqual(SupportConstants.REASON_OUTAGE, saved.Escalation_Reason__c);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, saved.Priority);
            Assert.areEqual(queues.get(SupportConstants.ROUTE_URGENT), saved.OwnerId);
            Assert.areEqual(1, logCount(c.Id, SupportConstants.TYPE_ESCALATION));
    
        }
    }

    @IsTest
    static void alreadyEscalatedCaseIsNotEscalatedOrRenotifiedAgain() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Need help', 'I want to talk to a human please.');
            Assert.areEqual(SupportConstants.REASON_HUMAN, SupportTestDataFactory.reload(c.Id).Escalation_Reason__c);

            // Simulate that the notification Flow already sent the notification.
            update new Case(Id = c.Id, Escalation_Notified__c = true);
            Id ownerBefore = SupportTestDataFactory.reload(c.Id).OwnerId;

            // A new description that matches a different (higher) escalation rule.
            update new Case(Id = c.Id, Description = 'Now the service is down for all users');
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Escalation_Notified__c, 'The notified flag must NOT be reset: no second notification.');
            Assert.areEqual(SupportConstants.REASON_HUMAN, saved.Escalation_Reason__c, 'The first escalation reason is kept.');
            Assert.areEqual(ownerBefore, saved.OwnerId, 'An already escalated case is not re-routed.');
            Assert.areEqual(1, logCount(c.Id, SupportConstants.TYPE_ESCALATION), 'Only one escalation audit entry.');
    
        }
    }

    @IsTest
    static void preProcessedCaseIsSkippedOnInsert() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.buildCase('Invoice problem', 'Wrong amount charged.');
            c.Intake_Processed__c = true;
            insert c;
            Assert.isNull(SupportTestDataFactory.reload(c.Id).Issue_Category__c, 'A case flagged as processed must not be processed again.');
    
        }
    }

    @IsTest
    static void bypassDisablesAutomation() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseTriggerHandler.bypass = true;
            Case c = SupportTestDataFactory.createCase('Invoice problem', 'Wrong amount charged.');
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isNull(saved.Issue_Category__c);
            Assert.isFalse(saved.Intake_Processed__c);
            Assert.areEqual(0, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id]);
    
        }
    }

    @IsTest
    static void failureInIntelligenceLayerNeverBlocksCaseCreation() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseTriggerHandler.simulateFailure = true;
            Case c = SupportTestDataFactory.createCase('Invoice problem', 'Wrong amount charged.');
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isNotNull(saved.Id, 'The case must still be saved.');
            Assert.isFalse(saved.Intake_Processed__c, 'The case stays unprocessed so Flow A or a later edit can process it.');

            List<AI_Interaction_Log__c> failures = [
                SELECT Outcome__c, Error_Message__c FROM AI_Interaction_Log__c WHERE Outcome__c = :SupportConstants.OUTCOME_FAILED
            ];
            Assert.areEqual(1, failures.size());
            Assert.isTrue(failures[0].Error_Message__c.contains('SupportException'));
    
        }
    }

    @IsTest
    static void emptyAndNullInputsAreIgnoredByHandler() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseTriggerHandler.run(TriggerOperation.BEFORE_INSERT, null, null);
            CaseTriggerHandler.run(TriggerOperation.BEFORE_INSERT, new List<Case>(), null);
            CaseTriggerHandler.run(TriggerOperation.BEFORE_DELETE, new List<Case>{ new Case(Subject = 'x') }, null);
            Assert.areEqual(0, [SELECT COUNT() FROM AI_Interaction_Log__c]);
    
        }
    }

    @IsTest
    static void shouldProcessLogic() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case oldCase = new Case(Subject = 'a', Description = 'b', AI_Failed_Attempts__c = 0);
            Assert.isTrue(CaseIntelligenceService.shouldProcess(new Case(Subject = 'a'), null), 'New unprocessed case');
            Assert.isFalse(CaseIntelligenceService.shouldProcess(new Case(Intake_Processed__c = true), null), 'New processed case');
            Assert.isTrue(CaseIntelligenceService.shouldProcess(new Case(Subject = 'changed', Description = 'b', AI_Failed_Attempts__c = 0), oldCase));
            Assert.isTrue(CaseIntelligenceService.shouldProcess(new Case(Subject = 'a', Description = 'changed', AI_Failed_Attempts__c = 0), oldCase));
            Assert.isTrue(CaseIntelligenceService.shouldProcess(new Case(Subject = 'a', Description = 'b', AI_Failed_Attempts__c = 1), oldCase));
            Assert.isFalse(CaseIntelligenceService.shouldProcess(new Case(Subject = 'a', Description = 'b', AI_Failed_Attempts__c = 0), oldCase));
    
        }
    }
}
