@IsTest
private class CaseIntelligenceServiceTest {

    @IsTest
    static void analyzeReturnsInsightWithRoutingAndEscalationInformation() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Service is down for all users', 'Nobody can open the dashboard.');

            CaseIntelligenceService.Insight insight = CaseIntelligenceService.analyze(c.Id);
            Assert.areEqual(c.Id, insight.caseId);
            Assert.areEqual(SupportConstants.CAT_TECHNICAL, insight.issueCategory);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, insight.recommendedPriority);
            Assert.isTrue(insight.escalationRecommended);
            Assert.isTrue(insight.humanHandoffRequired);
            Assert.areEqual(SupportConstants.REASON_OUTAGE, insight.escalationReason);
            Assert.areEqual(SupportTestDataFactory.QUEUE_PREFIX + 'Urgent', insight.recommendedQueue);
            Assert.isFalse(insight.troubleshootingSteps.isEmpty());
            Assert.isNotNull(insight.explanation);
            Assert.areEqual(SupportConstants.SOURCE_RULES, insight.source);
    
        }
    }

    @IsTest
    static void analyzeReportsMissingQueueMappingInsteadOfInventingAQueue() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            QueueRoutingService.mappingOverride = new Map<String, String>();
            Case c = SupportTestDataFactory.createCase('Invoice question', 'Please explain this charge.');
            Assert.areEqual('No queue mapping configured', CaseIntelligenceService.analyze(c.Id).recommendedQueue);
    
        }
    }

    @IsTest
    static void analyzeDoesNotChangeTheCase() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'Please explain this charge.');
            Datetime before = [SELECT SystemModstamp FROM Case WHERE Id = :c.Id].SystemModstamp;
            Integer dmlBefore = Limits.getDmlStatements();
            CaseIntelligenceService.analyze(c.Id);
            Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'analyze() is read-only: no DML at all.');
            Assert.areEqual(before, [SELECT SystemModstamp FROM Case WHERE Id = :c.Id].SystemModstamp);
    
        }
    }

    @IsTest
    static void analyzeRejectsNullAndUnknownCase() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            try {
                CaseIntelligenceService.analyze(null);
                Assert.fail('A null Id must be rejected.');
            } catch (SupportException e) {
                Assert.isTrue(e.getMessage().contains('required'));
            }

            Case c = SupportTestDataFactory.createCase('To delete', 'x');
            delete c;
            try {
                CaseIntelligenceService.analyze(c.Id);
                Assert.fail('A deleted case must not be found.');
            } catch (SupportException e) {
                Assert.isTrue(e.getMessage().contains('not found or you do not have access'));
            }
    
        }
    }

    @IsTest
    static void analyzeIsBlockedForUserWithoutCaseAccess() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'Please explain this charge.');
            User noAccess = SupportTestDataFactory.createNoAccessUser();
            if (noAccess == null) {
                return; // Minimum Access profile not available in this org: the scenario cannot be created.
            }
            System.runAs(noAccess) {
                try {
                    CaseIntelligenceService.analyze(c.Id);
                    Assert.fail('A user without Case access must not receive an analysis.');
                } catch (SupportException e) {
                    Assert.isTrue(e.getMessage().contains('not found or you do not have access'));
                }
            }
    
        }
    }

    @IsTest
    static void summarizeAndSavePersistsFieldsAndWritesAuditEntry() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'Please explain this charge on my statement.');
            update new Case(Id = c.Id, AI_Summary__c = 'old', AI_Recommended_Action__c = 'old');

            CaseIntelligenceService.Insight insight = CaseIntelligenceService.summarizeAndSave(c.Id);
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.areEqual(insight.summary, saved.AI_Summary__c);
            Assert.isTrue(saved.AI_Summary__c.contains('Billing'));
            Assert.areEqual(insight.recommendedPriority, saved.AI_Recommended_Priority__c);
            Assert.areNotEqual('old', saved.AI_Recommended_Action__c);

            List<AI_Interaction_Log__c> logs = [
                SELECT Outcome__c, Source__c, Request_Category__c FROM AI_Interaction_Log__c
                WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_SUMMARY
            ];
            Assert.areEqual(1, logs.size());
            Assert.areEqual(SupportConstants.OUTCOME_SUCCESS, logs[0].Outcome__c);
            Assert.areEqual(SupportConstants.SOURCE_RULES, logs[0].Source__c);
            Assert.areEqual(SupportConstants.CAT_BILLING, logs[0].Request_Category__c);
    
        }
    }

    @IsTest
    static void summaryDoesNotContainEmailAddressesOrLongNumbers() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Billing issue', 'Contact me at jane.doe@example.com, card 4111111111111111 was charged twice.');
            String summary = CaseIntelligenceService.analyze(c.Id).summary;
            Assert.isFalse(summary.contains('jane.doe@example.com'), 'E-mail addresses must be removed from summaries.');
            Assert.isFalse(summary.contains('4111111111111111'), 'Long numbers (card/phone) must be removed from summaries.');
            Assert.isTrue(summary.contains('[email]') && summary.contains('[number]'));
    
        }
    }

    @IsTest
    static void summarizeAndSaveFailsCleanlyWhenCaseIsNotAccessible() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('To delete', 'x');
            delete c;
            try {
                CaseIntelligenceService.summarizeAndSave(c.Id);
                Assert.fail('Expected SupportException');
            } catch (SupportException e) {
                Assert.isNotNull(e.getMessage());
            }
    
        }
    }

    @IsTest
    static void buildSummaryHandlesMissingSubjectAndDescription() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseRoutingRules.Decision d = CaseRoutingRules.evaluate(null);
            String summary = CaseIntelligenceService.buildSummary(null, null, d);
            Assert.isTrue(summary.contains('no subject provided'));
            Assert.isFalse(summary.contains('Customer reports'));
    
        }
    }

    @IsTest
    static void applyIntakeOnEmptyListReturnsZero() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.areEqual(0, CaseIntelligenceService.applyIntake(null, null));
            Assert.areEqual(0, CaseIntelligenceService.applyIntake(new List<Case>(), null));
    
        }
    }
}
