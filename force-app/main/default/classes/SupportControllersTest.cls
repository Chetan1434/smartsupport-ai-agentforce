/** Tests for SupportDashboardController and SupportAssistantController (the server side of the four LWCs). */
@IsTest
private class SupportControllersTest {

    @IsTest
    static void dashboardCountsReflectTheCasesTheUserCanSee() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            SupportTestDataFactory.createCase('Service is down for all users', 'Nobody can work.');          // outage: High + handoff
            SupportTestDataFactory.createCase('Terrible billing error', 'I am furious about the invoice.'); // negative
            SupportTestDataFactory.createCase('Question', 'Do you have a partner program?');                 // plain

            SupportDashboardController.DashboardData data = SupportDashboardController.getDashboardData();
            Assert.areEqual(3, data.openCases);
            Assert.areEqual(1, data.highPriorityCases);
            Assert.areEqual(1, data.humanAttentionCases);
            Assert.areEqual(1, data.escalatedCases);
            Assert.areEqual(1, data.negativeSentimentCases);

            Assert.areEqual(1, data.attentionCases.size(), 'Only the outage case is High priority or awaiting a human.');
            SupportDashboardController.CaseRow row = data.attentionCases[0];
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, row.priority);
            Assert.isTrue(row.humanHandoffRequired);
            Assert.areEqual(SupportConstants.CAT_TECHNICAL, row.issueCategory);
            Assert.isNotNull(row.recommendedAction);
            Assert.isNotNull(row.ownerName);

            Integer categoryTotal = 0;
            for (SupportDashboardController.CountRow c : data.openByCategory) {
                categoryTotal += c.total;
            }
            Assert.areEqual(3, categoryTotal, 'The category breakdown covers every open case.');

            Assert.isFalse(data.recentInteractions.isEmpty());
            Assert.isNotNull(data.recentInteractions[0].interactionType);
    
        }
    }

    @IsTest
    static void dashboardIsEmptyForEmptyOrg() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportDashboardController.DashboardData data = SupportDashboardController.getDashboardData();
            Assert.areEqual(0, data.openCases);
            Assert.isTrue(data.attentionCases.isEmpty());
            Assert.isTrue(data.recentInteractions.isEmpty());
    
        }
    }

    @IsTest
    static void dashboardRefusesUsersWithoutCaseAccess() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            User noAccess = SupportTestDataFactory.createNoAccessUser();
            if (noAccess == null) {
                return;
            }
            System.runAs(noAccess) {
                try {
                    SupportDashboardController.getDashboardData();
                    Assert.fail('A user without Case access must not receive dashboard data.');
                } catch (AuraHandledException e) {
                    Assert.isTrue(e.getMessage().contains('permission'));
                }
            }
    
        }
    }

    @IsTest
    static void insightAndSaveSummaryThroughController() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'Please explain this charge.');
            CaseIntelligenceService.Insight insight = SupportAssistantController.getInsight(c.Id);
            Assert.areEqual(SupportConstants.CAT_BILLING, insight.issueCategory);
            CaseIntelligenceService.Insight saved = SupportAssistantController.saveSummary(c.Id);
            Assert.areEqual(saved.summary, SupportTestDataFactory.reload(c.Id).AI_Summary__c);
    
        }
    }

    @IsTest
    static void controllerConvertsServiceErrorsToAuraHandledExceptionWithMessage() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            try {
                SupportAssistantController.getInsight(null);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('case Id is required'), 'The user-facing message must survive: ' + e.getMessage());
            }
            try {
                SupportAssistantController.saveSummary(null);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('case Id is required'));
            }
    
        }
    }

    @IsTest
    static void knowledgeSearchThroughControllerIsLoggedWithUiSource() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            KnowledgeSearchService.candidateOverride = new List<KnowledgeSearchService.Article>{
                new KnowledgeSearchService.Article('ka1', 'How to reset your password', 'Use the Forgot password link.', 'reset-password')
            };
            KnowledgeSearchService.SearchResult found = SupportAssistantController.searchKnowledge('How do I reset my password?', null);
            Assert.areEqual(SupportConstants.KB_FOUND, found.status);

            KnowledgeSearchService.candidateOverride = new List<KnowledgeSearchService.Article>();
            KnowledgeSearchService.SearchResult none = SupportAssistantController.searchKnowledge('refund policy enterprise', null);
            Assert.areEqual(SupportConstants.KB_INSUFFICIENT, none.status);

            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Interaction_Type__c = :SupportConstants.TYPE_KNOWLEDGE AND Source__c = :SupportConstants.SOURCE_UI AND Outcome__c = :SupportConstants.OUTCOME_SUCCESS]);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Interaction_Type__c = :SupportConstants.TYPE_KNOWLEDGE AND Source__c = :SupportConstants.SOURCE_UI AND Outcome__c = :SupportConstants.OUTCOME_INSUFFICIENT]);
    
        }
    }

    @IsTest
    static void caseActionsThroughController() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseActionService.ActionResult created = SupportAssistantController.createCase('Invoice question', 'Please explain this charge.', SupportConstants.PRIORITY_MEDIUM);
            Assert.isTrue(created.success, created.message);

            // The test user is an internal Standard user, so the e-mail is not required for the status lookup.
            CaseActionService.StatusResult status = SupportAssistantController.getCaseStatus(created.caseNumber, null);
            Assert.isTrue(status.found);
            Assert.areEqual(created.caseId, status.caseId);

            Assert.isTrue(SupportAssistantController.addComment(created.caseId, 'Looking into it.', false).success);

            SupportEscalationService.EscalationResult escalated = SupportAssistantController.escalateCase(created.caseId, SupportConstants.REASON_MANUAL);
            Assert.isTrue(escalated.success);
            Assert.isTrue(SupportAssistantController.requestHuman(created.caseId).alreadyEscalated);
    
        }
    }
}
