@IsTest
private class AIInteractionLogServiceTest {

    @IsTest
    static void logsValidEntryWithAllFields() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice', 'billing question');
            AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(c.Id, SupportConstants.TYPE_SUMMARY, SupportConstants.OUTCOME_SUCCESS, SupportConstants.SOURCE_AGENTFORCE);
            entry.requestCategory = 'Billing';
            entry.suggestedPriority = SupportConstants.PRIORITY_HIGH;
            entry.sentiment = SupportConstants.SENT_NEGATIVE;
            entry.recommendedAction = 'Call the customer';
            entry.handoffRequired = true;

            Assert.areEqual(1, AIInteractionLogService.log(entry));
            AI_Interaction_Log__c saved = [
                SELECT Case__c, Interaction_Type__c, Outcome__c, Source__c, Request_Category__c, Suggested_Priority__c,
                       Sentiment__c, Recommended_Action__c, Human_Handoff_Required__c
                FROM AI_Interaction_Log__c
                WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_SUMMARY AND Source__c = :SupportConstants.SOURCE_AGENTFORCE
            ];
            Assert.areEqual(SupportConstants.OUTCOME_SUCCESS, saved.Outcome__c);
            Assert.areEqual('Billing', saved.Request_Category__c);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, saved.Suggested_Priority__c);
            Assert.areEqual(SupportConstants.SENT_NEGATIVE, saved.Sentiment__c);
            Assert.areEqual('Call the customer', saved.Recommended_Action__c);
            Assert.isTrue(saved.Human_Handoff_Required__c);
    
        }
    }

    @IsTest
    static void invalidTypeIsSkippedAndInvalidPicklistsFallBackSafely() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.areEqual(0, AIInteractionLogService.log(new AIInteractionLogService.LogEntry(null, 'Not A Type', SupportConstants.OUTCOME_SUCCESS, SupportConstants.SOURCE_RULES)));
            Assert.areEqual(0, AIInteractionLogService.log((AIInteractionLogService.LogEntry) null));
            Assert.areEqual(0, AIInteractionLogService.log((List<AIInteractionLogService.LogEntry>) null));
            Assert.areEqual(0, AIInteractionLogService.log(new List<AIInteractionLogService.LogEntry>()));

            AIInteractionLogService.LogEntry odd = new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_STATUS, 'Weird', 'Nowhere');
            odd.suggestedPriority = 'Urgent!!';
            odd.sentiment = 'Furious';
            Assert.areEqual(1, AIInteractionLogService.log(odd));
            AI_Interaction_Log__c saved = [SELECT Outcome__c, Source__c, Suggested_Priority__c, Sentiment__c FROM AI_Interaction_Log__c];
            Assert.areEqual(SupportConstants.OUTCOME_FAILED, saved.Outcome__c);
            Assert.areEqual(SupportConstants.SOURCE_RULES, saved.Source__c);
            Assert.isNull(saved.Suggested_Priority__c);
            Assert.isNull(saved.Sentiment__c);
    
        }
    }

    @IsTest
    static void bulkEntriesAreInsertedInOneDmlStatement() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            List<AIInteractionLogService.LogEntry> entries = new List<AIInteractionLogService.LogEntry>();
            for (Integer i = 0; i < 100; i++) {
                entries.add(new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_KNOWLEDGE, SupportConstants.OUTCOME_INSUFFICIENT, SupportConstants.SOURCE_UI));
            }
            Integer dmlBefore = Limits.getDmlStatements();
            Assert.areEqual(100, AIInteractionLogService.log(entries));
            Assert.areEqual(1, Limits.getDmlStatements() - dmlBefore, 'All entries must be written with a single DML statement.');
    
        }
    }

    @IsTest
    static void sanitizeRemovesPiiCollapsesWhitespaceAndTruncates() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isNull(AIInteractionLogService.sanitize(null, 255));
            Assert.isNull(AIInteractionLogService.sanitize('   ', 255));
            Assert.areEqual('Contact [email] about [number]', AIInteractionLogService.sanitize('Contact bob@example.com about 123456789', 255));
            Assert.areEqual('a b', AIInteractionLogService.sanitize('a\n\tb', 255));
            Assert.areEqual(10, AIInteractionLogService.sanitize('x'.repeat(500), 10).length());
            Assert.areEqual(255, AIInteractionLogService.sanitize('x'.repeat(500), null).length(), 'A missing limit falls back to 255.');
            Assert.areEqual('12345', AIInteractionLogService.sanitize('12345', 255), 'Short numbers are not PII.');
    
        }
    }

    @IsTest
    static void errorMessagesAreSanitizedBeforeStorage() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_CLASSIFICATION, SupportConstants.OUTCOME_FAILED, SupportConstants.SOURCE_RULES);
            entry.errorMessage = 'Failed for user jane@example.com phone 5551234567';
            AIInteractionLogService.log(entry);
            String stored = [SELECT Error_Message__c FROM AI_Interaction_Log__c].Error_Message__c;
            Assert.isFalse(stored.contains('jane@example.com'));
            Assert.isFalse(stored.contains('5551234567'));
    
        }
    }

    @IsTest
    static void fromCaseCopiesPersistedAiFields() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Terrible billing error', 'I am furious about the invoice.');
            AIInteractionLogService.LogEntry entry = AIInteractionLogService.fromCase(SupportTestDataFactory.reload(c.Id), SupportConstants.TYPE_CLASSIFICATION, SupportConstants.OUTCOME_SUCCESS, SupportConstants.SOURCE_RULES);
            Assert.areEqual(c.Id, entry.caseId);
            Assert.areEqual(SupportConstants.CAT_BILLING, entry.requestCategory);
            Assert.areEqual(SupportConstants.SENT_NEGATIVE, entry.sentiment);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, entry.suggestedPriority);
    
        }
    }

    @IsTest
    static void logSurvivesDeletionOfTheCase() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice', 'billing question');
            Integer before = [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id];
            Assert.isTrue(before > 0);
            delete c;
            Assert.areEqual(before, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = null AND Interaction_Type__c = :SupportConstants.TYPE_CLASSIFICATION], 'Lookup with SetNull keeps audit rows after the case is deleted.');
    
        }
    }
}
