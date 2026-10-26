/** Tests for AgentforceActionService and the seven AgentAction* invocable classes. */
@IsTest
private class AgentforceActionsTest {

    private static List<KnowledgeSearchService.Article> unrelatedArticles() {
        return new List<KnowledgeSearchService.Article>{
            new KnowledgeSearchService.Article('ka2', 'Shipping times', 'Standard delivery takes three to five business days.', 'shipping-times')
        };
    }

    // ----- toId -----
    @IsTest
    static void toIdAcceptsOnlyWellFormedIds() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('x', 'y');
            Assert.areEqual(c.Id, AgentforceActionService.toId(String.valueOf(c.Id)));
            Assert.areEqual(c.Id, AgentforceActionService.toId('  ' + String.valueOf(c.Id) + ' '));
            Assert.isNull(AgentforceActionService.toId(null));
            Assert.isNull(AgentforceActionService.toId(''));
            Assert.isNull(AgentforceActionService.toId('12345'));
            Assert.isNull(AgentforceActionService.toId('not-an-id-at-all!!'));
            Assert.isNull(AgentforceActionService.toId('500' + 'Z'.repeat(15)), 'Right length but not a valid Id.');
    
        }
    }

    // ----- knowledge -----
    @IsTest
    static void searchKnowledgeActionReturnsGroundedAnswerWithSources() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            KnowledgeSearchService.candidateOverride = new List<KnowledgeSearchService.Article>{
                new KnowledgeSearchService.Article('ka1', 'How to reset your password', 'Use the Forgot password link on the login page.', 'reset-password')
            };
            AgentActionSearchKnowledge.Request req = new AgentActionSearchKnowledge.Request();
            req.question = 'How do I reset my password?';
            List<AgentActionSearchKnowledge.Response> res = AgentActionSearchKnowledge.run(new List<AgentActionSearchKnowledge.Request>{ req });

            Assert.areEqual(1, res.size());
            Assert.areEqual(SupportConstants.KB_FOUND, res[0].status);
            Assert.isTrue(res[0].answer.contains('Forgot password link'));
            Assert.isTrue(res[0].sources.contains('How to reset your password'));
            Assert.isTrue(res[0].sources.contains('reset-password'));
            Assert.isFalse(res[0].humanRecommended);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Interaction_Type__c = :SupportConstants.TYPE_KNOWLEDGE AND Outcome__c = :SupportConstants.OUTCOME_SUCCESS AND Source__c = :SupportConstants.SOURCE_AGENTFORCE]);
    
        }
    }

    @IsTest
    static void searchKnowledgeWithoutEvidenceRecommendsHumanAndCountsAFailedAttempt() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            KnowledgeSearchService.candidateOverride = unrelatedArticles();
            Case c = SupportTestDataFactory.createCase('Question about contracts', 'Need info');
            AgentActionSearchKnowledge.Request req = new AgentActionSearchKnowledge.Request();
            req.question = 'What is your refund policy for enterprise contracts?';
            req.caseId = String.valueOf(c.Id);
            AgentActionSearchKnowledge.Response res = AgentActionSearchKnowledge.run(new List<AgentActionSearchKnowledge.Request>{ req })[0];

            Assert.areEqual(SupportConstants.KB_INSUFFICIENT, res.status);
            Assert.isNull(res.answer, 'The agent must not receive an invented answer.');
            Assert.isTrue(res.humanRecommended);
            Assert.areEqual(1, SupportTestDataFactory.reload(c.Id).AI_Failed_Attempts__c);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Outcome__c = :SupportConstants.OUTCOME_INSUFFICIENT]);
    
        }
    }

    @IsTest
    static void twoUnsuccessfulSearchesHandTheCaseToAHuman() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            KnowledgeSearchService.candidateOverride = unrelatedArticles();
            Case c = SupportTestDataFactory.createCase('Question about contracts', 'Need info');
            for (Integer i = 0; i < SupportConstants.failedAttemptThreshold(); i++) {
                AgentforceActionService.searchKnowledge('What is your refund policy for enterprise contracts?', String.valueOf(c.Id));
            }
            Case saved = SupportTestDataFactory.reload(c.Id);
            Assert.isTrue(saved.Human_Handoff_Required__c, 'Repeated unsuccessful assistance must trigger a handoff.');
            Assert.areEqual(SupportConstants.REASON_AI_FAILURE, saved.Escalation_Reason__c);
    
        }
    }

    @IsTest
    static void searchKnowledgeHandlesInvalidInputAndNullRequests() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            AgentActionSearchKnowledge.Request req = new AgentActionSearchKnowledge.Request();
            req.question = '   ';
            Assert.areEqual(SupportConstants.KB_INVALID, AgentActionSearchKnowledge.run(new List<AgentActionSearchKnowledge.Request>{ req })[0].status);
            Assert.isTrue(AgentActionSearchKnowledge.run(null).isEmpty());
            Assert.areEqual(SupportConstants.KB_INVALID, AgentActionSearchKnowledge.run(new List<AgentActionSearchKnowledge.Request>{ null })[0].status);
    
        }
    }

    // ----- classify / summarize -----
    @IsTest
    static void classifyActionReturnsRecommendationsWithoutChangingTheCase() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Possible data breach', 'We see unauthorized access.');
            AgentActionClassifyCase.Request req = new AgentActionClassifyCase.Request();
            req.caseId = String.valueOf(c.Id);
            AgentActionClassifyCase.Response res = AgentActionClassifyCase.run(new List<AgentActionClassifyCase.Request>{ req })[0];

            Assert.isTrue(res.success);
            Assert.areEqual(SupportConstants.CAT_SECURITY, res.issueCategory);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, res.recommendedPriority);
            Assert.isTrue(res.escalationRecommended);
            Assert.areEqual(SupportConstants.REASON_SECURITY, res.escalationReason);
            Assert.areEqual(SupportTestDataFactory.QUEUE_PREFIX + 'Security', res.recommendedQueue);
            Assert.isNotNull(res.explanation);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_CLASSIFICATION AND Source__c = :SupportConstants.SOURCE_AGENTFORCE]);
    
        }
    }

    @IsTest
    static void classifyAndSummarizeRejectInvalidIds() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            AgentActionClassifyCase.Request classify = new AgentActionClassifyCase.Request();
            classify.caseId = 'garbage';
            AgentActionClassifyCase.Response c = AgentActionClassifyCase.run(new List<AgentActionClassifyCase.Request>{ classify })[0];
            Assert.isFalse(c.success);
            Assert.isNull(c.issueCategory);
            Assert.isTrue(c.message.contains('valid case Id'));

            AgentActionSummarizeCase.Request summarize = new AgentActionSummarizeCase.Request();
            AgentActionSummarizeCase.Response s = AgentActionSummarizeCase.run(new List<AgentActionSummarizeCase.Request>{ summarize })[0];
            Assert.isFalse(s.success);
            Assert.isTrue(s.humanReviewRequired, 'When nothing could be summarized a human must look at it.');
    
        }
    }

    @IsTest
    static void classifyForDeletedCaseReturnsAccessMessage() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('x', 'y');
            delete c;
            AgentActionClassifyCase.Request req = new AgentActionClassifyCase.Request();
            req.caseId = String.valueOf(c.Id);
            AgentActionClassifyCase.Response res = AgentActionClassifyCase.run(new List<AgentActionClassifyCase.Request>{ req })[0];
            Assert.isFalse(res.success);
            Assert.isTrue(res.message.contains('not found or you do not have access'));
    
        }
    }

    @IsTest
    static void summarizeActionSavesSummary() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'Please explain this charge.');
            AgentActionSummarizeCase.Request req = new AgentActionSummarizeCase.Request();
            req.caseId = String.valueOf(c.Id);
            AgentActionSummarizeCase.Response res = AgentActionSummarizeCase.run(new List<AgentActionSummarizeCase.Request>{ req })[0];
            Assert.isTrue(res.success);
            Assert.isTrue(res.summary.contains('Billing'));
            Assert.isNotNull(res.recommendedAction);
            Assert.areEqual(res.summary, SupportTestDataFactory.reload(c.Id).AI_Summary__c);
    
        }
    }

    // ----- status -----
    @IsTest
    static void statusActionAlwaysRequiresTheVerifiedEmail() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Account a = SupportTestDataFactory.createAccount('Acme', 'Standard');
            Contact contact = SupportTestDataFactory.createContact(a.Id, 'Rao', 'rao@example.com');
            Case c = SupportTestDataFactory.buildCase('Invoice question', 'billing');
            c.ContactId = contact.Id;
            insert c;
            String lookupNumber = SupportTestDataFactory.reload(c.Id).CaseNumber;

            AgentActionGetCaseStatus.Request withoutEmail = new AgentActionGetCaseStatus.Request();
            withoutEmail.caseNumber = lookupNumber;
            AgentActionGetCaseStatus.Response denied = AgentActionGetCaseStatus.run(new List<AgentActionGetCaseStatus.Request>{ withoutEmail })[0];
            Assert.isFalse(denied.found, 'Even an internal/agent user must supply the verified e-mail through the action.');
            Assert.isNull(denied.subject);

            AgentActionGetCaseStatus.Request verified = new AgentActionGetCaseStatus.Request();
            verified.caseNumber = lookupNumber;
            verified.verifiedContactEmail = 'rao@example.com';
            AgentActionGetCaseStatus.Response ok = AgentActionGetCaseStatus.run(new List<AgentActionGetCaseStatus.Request>{ verified })[0];
            Assert.isTrue(ok.found);
            Assert.areEqual(String.valueOf(c.Id), ok.caseId);
            Assert.areEqual('Invoice question', ok.subject);
    
        }
    }

    // ----- create -----
    @IsTest
    static void createActionCreatesClassifiedCaseAndValidatesContact() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            AgentActionCreateCase.Request req = new AgentActionCreateCase.Request();
            req.subject = 'Cannot log in';
            req.description = 'I forgot my password.';
            AgentActionCreateCase.Response res = AgentActionCreateCase.run(new List<AgentActionCreateCase.Request>{ req })[0];
            Assert.isTrue(res.success, res.message);
            Assert.areEqual(SupportConstants.CAT_ACCESS, res.issueCategory);
            Assert.isNotNull(res.caseNumber);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Interaction_Type__c = :SupportConstants.TYPE_CASE_CREATED AND Source__c = :SupportConstants.SOURCE_AGENTFORCE]);

            AgentActionCreateCase.Request badContact = new AgentActionCreateCase.Request();
            badContact.subject = 'Another';
            badContact.contactId = 'not-an-id';
            AgentActionCreateCase.Response denied = AgentActionCreateCase.run(new List<AgentActionCreateCase.Request>{ badContact })[0];
            Assert.isFalse(denied.success);
            Assert.isTrue(denied.message.contains('contact Id is not valid'));
            Assert.areEqual(1, [SELECT COUNT() FROM Case], 'The invalid request must not create a case.');
    
        }
    }

    @IsTest
    static void createActionRejectsMissingSubject() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            AgentActionCreateCase.Response res = AgentActionCreateCase.run(new List<AgentActionCreateCase.Request>{ new AgentActionCreateCase.Request() })[0];
            Assert.isFalse(res.success);
            Assert.isTrue(res.message.contains('subject is required'));
    
        }
    }

    // ----- comment -----
    @IsTest
    static void commentActionAddsAnInternalCommentOnly() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            AgentActionAddComment.Request req = new AgentActionAddComment.Request();
            req.caseId = String.valueOf(c.Id);
            req.comment = 'Customer confirmed the invoice number.';
            Assert.isTrue(AgentActionAddComment.run(new List<AgentActionAddComment.Request>{ req })[0].success);
            Assert.isFalse([SELECT IsPublished FROM CaseComment WHERE ParentId = :c.Id].IsPublished, 'Agent comments are internal so a human can review them first.');
    
        }
    }

    @IsTest
    static void commentActionValidatesInput() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            AgentActionAddComment.Request bad = new AgentActionAddComment.Request();
            bad.caseId = 'nope';
            bad.comment = 'x';
            AgentActionAddComment.Response res = AgentActionAddComment.run(new List<AgentActionAddComment.Request>{ bad })[0];
            Assert.isFalse(res.success);
            Assert.isTrue(res.message.contains('valid case Id'));
    
        }
    }

    // ----- escalate -----
    @IsTest
    static void escalateActionEscalatesOnceAndIsIdempotent() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            SupportTestDataFactory.createQueuesAndMapping();
            Case c = SupportTestDataFactory.createCase('Question', 'How do I export a report?');
            AgentActionEscalateCase.Request req = new AgentActionEscalateCase.Request();
            req.caseId = String.valueOf(c.Id);
            req.reason = SupportConstants.REASON_NO_KNOWLEDGE;

            AgentActionEscalateCase.Response first = AgentActionEscalateCase.run(new List<AgentActionEscalateCase.Request>{ req })[0];
            Assert.isTrue(first.success);
            Assert.isFalse(first.alreadyEscalated);
            Assert.areEqual(SupportConstants.REASON_NO_KNOWLEDGE, SupportTestDataFactory.reload(c.Id).Escalation_Reason__c);

            AgentActionEscalateCase.Response second = AgentActionEscalateCase.run(new List<AgentActionEscalateCase.Request>{ req })[0];
            Assert.isTrue(second.alreadyEscalated);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_ESCALATION]);
            Assert.areEqual(SupportConstants.SOURCE_AGENTFORCE, [SELECT Source__c FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_ESCALATION].Source__c);
    
        }
    }

    @IsTest
    static void escalateActionRejectsInvalidReasonAndInvalidId() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Question', 'x');
            AgentActionEscalateCase.Request badReason = new AgentActionEscalateCase.Request();
            badReason.caseId = String.valueOf(c.Id);
            badReason.reason = 'Because';
            Assert.isFalse(AgentActionEscalateCase.run(new List<AgentActionEscalateCase.Request>{ badReason })[0].success);

            AgentActionEscalateCase.Request badId = new AgentActionEscalateCase.Request();
            badId.caseId = 'bogus';
            AgentActionEscalateCase.Response res = AgentActionEscalateCase.run(new List<AgentActionEscalateCase.Request>{ badId })[0];
            Assert.isFalse(res.success);
            Assert.isTrue(res.message.contains('valid case Id'));
            Assert.isFalse(SupportTestDataFactory.reload(c.Id).Human_Handoff_Required__c);
    
        }
    }

    // ----- bulk / null -----
    @IsTest
    static void everyActionIsBulkSafeAndNullSafe() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isTrue(AgentActionClassifyCase.run(null).isEmpty());
            Assert.isTrue(AgentActionSummarizeCase.run(null).isEmpty());
            Assert.isTrue(AgentActionGetCaseStatus.run(null).isEmpty());
            Assert.isTrue(AgentActionCreateCase.run(null).isEmpty());
            Assert.isTrue(AgentActionAddComment.run(null).isEmpty());
            Assert.isTrue(AgentActionEscalateCase.run(null).isEmpty());

            List<AgentActionCreateCase.Request> requests = new List<AgentActionCreateCase.Request>();
            for (Integer i = 0; i < 5; i++) {
                AgentActionCreateCase.Request r = new AgentActionCreateCase.Request();
                r.subject = 'Invoice ' + i;
                requests.add(r);
            }
            requests.add(null);
            List<AgentActionCreateCase.Response> responses = AgentActionCreateCase.run(requests);
            Assert.areEqual(6, responses.size(), 'One response per request, in order.');
            Assert.isTrue(responses[0].success);
            Assert.isFalse(responses[5].success, 'A null request produces a failure response, not an exception.');
    
        }
    }
}
