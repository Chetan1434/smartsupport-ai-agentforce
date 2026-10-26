@IsTest
private class CaseActionServiceTest {

    // ----- create -----
    @IsTest
    static void createCaseSucceedsIsClassifiedAndAudited() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseActionService.ActionResult result = CaseActionService.createCase('Invoice question', 'Please explain the charge.', SupportConstants.PRIORITY_HIGH, null, SupportConstants.SOURCE_UI);
            Assert.isTrue(result.success, result.message);
            Assert.isNotNull(result.caseId);
            Assert.isNotNull(result.caseNumber);
            Assert.areEqual(SupportConstants.CAT_BILLING, result.issueCategory, 'The trigger classification is visible to the caller.');
            Assert.isFalse(result.humanHandoffRequired);
            Case saved = SupportTestDataFactory.reload(result.caseId);
            Assert.areEqual(SupportConstants.PRIORITY_HIGH, saved.Priority);
            Assert.areEqual(1, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :result.caseId AND Interaction_Type__c = :SupportConstants.TYPE_CASE_CREATED AND Outcome__c = :SupportConstants.OUTCOME_SUCCESS]);
    
        }
    }

    @IsTest
    static void createCaseWithOutageReportsHandoff() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            CaseActionService.ActionResult result = CaseActionService.createCase('Service is down for all users', 'Nobody can work.', null, null, SupportConstants.SOURCE_AGENTFORCE);
            Assert.isTrue(result.success);
            Assert.isTrue(result.humanHandoffRequired);
    
        }
    }

    @IsTest
    static void createCaseValidatesEveryInput() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Assert.isFalse(CaseActionService.createCase(null, 'x', null, null, SupportConstants.SOURCE_UI).success);
            Assert.isFalse(CaseActionService.createCase('  ', 'x', null, null, SupportConstants.SOURCE_UI).success);
            CaseActionService.ActionResult longSubject = CaseActionService.createCase('s'.repeat(256), 'x', null, null, SupportConstants.SOURCE_UI);
            Assert.isFalse(longSubject.success);
            Assert.isTrue(longSubject.message.contains('too long'));
            Assert.isFalse(CaseActionService.createCase('ok', 'd'.repeat(SupportConstants.MAX_DESCRIPTION_LENGTH + 1), null, null, SupportConstants.SOURCE_UI).success);
            CaseActionService.ActionResult badPriority = CaseActionService.createCase('ok', 'x', 'Urgent', null, SupportConstants.SOURCE_UI);
            Assert.isFalse(badPriority.success);
            Assert.isTrue(badPriority.message.contains('High, Medium or Low'));
            Assert.areEqual(0, [SELECT COUNT() FROM Case], 'Nothing may be created for invalid input.');
    
        }
    }

    @IsTest
    static void createCaseFailsCleanlyWithoutPermission() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            User noAccess = SupportTestDataFactory.createNoAccessUser();
            if (noAccess == null) {
                return;
            }
            System.runAs(noAccess) {
                CaseActionService.ActionResult result = CaseActionService.createCase('Invoice', 'x', null, null, SupportConstants.SOURCE_UI);
                Assert.isFalse(result.success);
                Assert.isTrue(result.message.contains('permission'));
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Case]);
    
        }
    }

    // ----- status -----
    @IsTest
    static void internalUserCanReadAccessibleCaseWithoutEmail() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            String lookupNumber = SupportTestDataFactory.reload(c.Id).CaseNumber;
            CaseActionService.StatusResult result = CaseActionService.getCaseStatus(lookupNumber, null, false, SupportConstants.SOURCE_UI);
            Assert.isTrue(result.found);
            Assert.areEqual(c.Id, result.caseId);
            Assert.areEqual(lookupNumber, result.caseNumber);
            Assert.isNotNull(result.status);
            Assert.isTrue(result.message.contains(lookupNumber));
    
        }
    }

    @IsTest
    static void customerFacingLookupRequiresMatchingContactEmail() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Account a = SupportTestDataFactory.createAccount('Acme', 'Standard');
            Contact contact = SupportTestDataFactory.createContact(a.Id, 'Rao', 'rao@example.com');
            Case c = SupportTestDataFactory.buildCase('Invoice question', 'billing');
            c.ContactId = contact.Id;
            insert c;
            String lookupNumber = SupportTestDataFactory.reload(c.Id).CaseNumber;

            CaseActionService.StatusResult noEmail = CaseActionService.getCaseStatus(lookupNumber, null, true, SupportConstants.SOURCE_AGENTFORCE);
            Assert.isFalse(noEmail.found, 'A case number alone must never be enough.');
            Assert.isTrue(noEmail.message.contains('e-mail address'));
            Assert.isNull(noEmail.subject);

            CaseActionService.StatusResult wrongEmail = CaseActionService.getCaseStatus(lookupNumber, 'someone.else@example.com', true, SupportConstants.SOURCE_AGENTFORCE);
            Assert.isFalse(wrongEmail.found);
            Assert.isNull(wrongEmail.subject, 'No case data may leak on a mismatch.');

            CaseActionService.StatusResult unknownCase = CaseActionService.getCaseStatus('99999999', 'rao@example.com', true, SupportConstants.SOURCE_AGENTFORCE);
            Assert.isFalse(unknownCase.found);
            Assert.areEqual(unknownCase.message, wrongEmail.message, 'Unknown case and wrong e-mail look identical (no enumeration).');

            CaseActionService.StatusResult ok = CaseActionService.getCaseStatus(lookupNumber, '  RAO@Example.com ', true, SupportConstants.SOURCE_AGENTFORCE);
            Assert.isTrue(ok.found, 'E-mail comparison ignores case and surrounding spaces.');
            Assert.areEqual(c.Id, ok.caseId);

            Assert.isTrue([SELECT COUNT() FROM AI_Interaction_Log__c WHERE Outcome__c = :SupportConstants.OUTCOME_BLOCKED AND Interaction_Type__c = :SupportConstants.TYPE_STATUS] >= 2, 'Blocked lookups are audited.');
    
        }
    }

    @IsTest
    static void caseWithoutContactCannotBeVerifiedByEmail() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            String lookupNumber = SupportTestDataFactory.reload(c.Id).CaseNumber;
            Assert.isFalse(CaseActionService.getCaseStatus(lookupNumber, 'any@example.com', true, SupportConstants.SOURCE_AGENTFORCE).found);
    
        }
    }

    @IsTest
    static void malformedCaseNumbersAreRejectedWithoutQuerying() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Integer queriesBefore = Limits.getQueries();
            Assert.isFalse(CaseActionService.getCaseStatus(null, null, false, SupportConstants.SOURCE_UI).found);
            Assert.isFalse(CaseActionService.getCaseStatus('', null, false, SupportConstants.SOURCE_UI).found);
            Assert.isFalse(CaseActionService.getCaseStatus('0001\' OR Id != null --', null, false, SupportConstants.SOURCE_UI).found);
            Assert.isFalse(CaseActionService.getCaseStatus('1'.repeat(31), null, false, SupportConstants.SOURCE_UI).found);
            Assert.areEqual(queriesBefore, Limits.getQueries(), 'Invalid input must not reach the database.');
    
        }
    }

    @IsTest
    static void userWithoutCaseAccessCannotReadStatus() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            String lookupNumber = SupportTestDataFactory.reload(c.Id).CaseNumber;
            User noAccess = SupportTestDataFactory.createNoAccessUser();
            if (noAccess == null) {
                return;
            }
            System.runAs(noAccess) {
                Assert.isFalse(CaseActionService.getCaseStatus(lookupNumber, null, false, SupportConstants.SOURCE_UI).found);
            }
    
        }
    }

    // ----- comments -----
    @IsTest
    static void addCommentStoresInternalAndPublicComments() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            Assert.isTrue(CaseActionService.addComment(c.Id, '  Called the customer.  ', false, SupportConstants.SOURCE_UI).success);
            Assert.isTrue(CaseActionService.addComment(c.Id, 'We are looking into it.', true, SupportConstants.SOURCE_UI).success);

            List<CaseComment> comments = [SELECT CommentBody, IsPublished FROM CaseComment WHERE ParentId = :c.Id ORDER BY CreatedDate, Id];
            Assert.areEqual(2, comments.size());
            Assert.areEqual('Called the customer.', comments[0].CommentBody);
            Assert.isFalse(comments[0].IsPublished);
            Assert.isTrue(comments[1].IsPublished);
            Assert.areEqual(2, [SELECT COUNT() FROM AI_Interaction_Log__c WHERE Case__c = :c.Id AND Interaction_Type__c = :SupportConstants.TYPE_COMMENT]);
    
        }
    }

    @IsTest
    static void addCommentValidatesInput() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            Assert.isFalse(CaseActionService.addComment(null, 'x', false, SupportConstants.SOURCE_UI).success);
            Assert.isFalse(CaseActionService.addComment(c.Id, null, false, SupportConstants.SOURCE_UI).success);
            Assert.isFalse(CaseActionService.addComment(c.Id, '   ', false, SupportConstants.SOURCE_UI).success);
            CaseActionService.ActionResult tooLong = CaseActionService.addComment(c.Id, 'x'.repeat(SupportConstants.MAX_COMMENT_LENGTH + 1), false, SupportConstants.SOURCE_UI);
            Assert.isFalse(tooLong.success);
            Assert.isTrue(tooLong.message.contains('too long'));
            Assert.areEqual(0, [SELECT COUNT() FROM CaseComment]);
    
        }
    }

    @IsTest
    static void addCommentToInaccessibleCaseIsRejected() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('x', 'y');
            delete c;
            CaseActionService.ActionResult result = CaseActionService.addComment(c.Id, 'hello', false, SupportConstants.SOURCE_UI);
            Assert.isFalse(result.success);
            Assert.isTrue(result.message.contains('not found or you do not have access'));
    
        }
    }

    // ----- approved field update -----
    @IsTest
    static void updateApprovedFieldChangesOnlyWhitelistedFieldsWithValidValues() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            CaseActionService.ActionResult ok = CaseActionService.updateApprovedField(c.Id, 'Priority', SupportConstants.PRIORITY_LOW);
            Assert.isTrue(ok.success, ok.message);
            Assert.areEqual(SupportConstants.PRIORITY_LOW, SupportTestDataFactory.reload(c.Id).Priority);

            Assert.isTrue(CaseActionService.updateApprovedField(c.Id, 'Issue_Category__c', SupportConstants.CAT_SHIPPING).success);
            Assert.areEqual(SupportConstants.CAT_SHIPPING, SupportTestDataFactory.reload(c.Id).Issue_Category__c);
    
        }
    }

    @IsTest
    static void updateApprovedFieldRejectsUnapprovedFieldsAndInvalidValues() {
        System.runAs(SupportTestDataFactory.supportUser()) {
            Case c = SupportTestDataFactory.createCase('Invoice question', 'billing');
            Id ownerBefore = SupportTestDataFactory.reload(c.Id).OwnerId;

            CaseActionService.ActionResult owner = CaseActionService.updateApprovedField(c.Id, 'OwnerId', String.valueOf(UserInfo.getUserId()));
            Assert.isFalse(owner.success);
            Assert.isTrue(owner.message.contains('cannot be changed here'));
            Assert.isFalse(CaseActionService.updateApprovedField(c.Id, 'Subject', 'Hacked').success);
            Assert.isFalse(CaseActionService.updateApprovedField(c.Id, 'Priority', 'Super Urgent').success);
            Assert.isFalse(CaseActionService.updateApprovedField(c.Id, 'Priority', null).success);
            Assert.isFalse(CaseActionService.updateApprovedField(null, 'Priority', 'Low').success);
            Assert.areEqual(ownerBefore, SupportTestDataFactory.reload(c.Id).OwnerId);
            Assert.areEqual('Invoice question', SupportTestDataFactory.reload(c.Id).Subject);
    
        }
    }
}
