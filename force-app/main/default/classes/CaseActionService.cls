/**
 * Controlled case operations used by the LWC controller and the Agentforce actions.
 *
 * Every operation:
 *   - validates its input (null, blank, length, allowed values),
 *   - runs in USER mode (object permissions, field-level security and record sharing of the running user),
 *   - returns a result object instead of throwing, so callers can show a clear message,
 *   - writes an audit entry through AIInteractionLogService.
 *
 * There is NO method that accepts a free-form query, field name list or arbitrary SObject.
 */
public with sharing class CaseActionService {
    /** The only fields updateApprovedField() may change. */
    @TestVisible private static final Set<String> APPROVED_FIELDS = new Set<String>{ 'Priority', 'Status', 'Issue_Category__c' };

    public class ActionResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean humanHandoffRequired = false;
        @AuraEnabled public String issueCategory;
    }

    public class StatusResult {
        @AuraEnabled public Boolean found = false;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String lastUpdated;
        @AuraEnabled public Boolean humanHandoffRequired = false;
        @AuraEnabled public Boolean escalated = false;
        @AuraEnabled public String message;
    }

    // ---------------------------------------------------------------------------------------------
    // Create
    // ---------------------------------------------------------------------------------------------
    public static ActionResult createCase(String subject, String description, String priority, Id contactId, String source) {
        ActionResult result = new ActionResult();
        if (String.isBlank(subject)) {
            result.message = 'A subject is required.';
            return result;
        }
        if (subject.length() > SupportConstants.MAX_SUBJECT_LENGTH) {
            result.message = 'The subject is too long (maximum ' + SupportConstants.MAX_SUBJECT_LENGTH + ' characters).';
            return result;
        }
        if (description != null && description.length() > SupportConstants.MAX_DESCRIPTION_LENGTH) {
            result.message = 'The description is too long.';
            return result;
        }
        if (String.isNotBlank(priority) && !SupportConstants.VALID_PRIORITIES.contains(priority)) {
            result.message = 'Priority must be High, Medium or Low.';
            return result;
        }

        Case c = new Case(Subject = subject.trim(), Description = description);
        if (String.isNotBlank(priority)) {
            c.Priority = priority;
        }
        if (contactId != null) {
            c.ContactId = contactId;
        }
        try {
            Database.insert(c, AccessLevel.USER_MODE);
        } catch (Exception e) {
            result.message = 'The case could not be created. You may not have permission to create cases.';
            AIInteractionLogService.LogEntry failed = new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_CASE_CREATED, SupportConstants.OUTCOME_FAILED, source);
            failed.errorMessage = e.getTypeName();
            AIInteractionLogService.log(failed);
            return result;
        }

        // Re-read so the trigger results (case number, category, handoff) are visible to the caller.
        List<Case> created = [SELECT Id, CaseNumber, Issue_Category__c, Human_Handoff_Required__c FROM Case WHERE Id = :c.Id WITH USER_MODE LIMIT 1];
        result.success = true;
        result.caseId = c.Id;
        if (!created.isEmpty()) {
            result.caseNumber = created[0].CaseNumber;
            result.issueCategory = created[0].Issue_Category__c;
            result.humanHandoffRequired = created[0].Human_Handoff_Required__c == true;
        }
        result.message = 'Case ' + (result.caseNumber == null ? '' : result.caseNumber + ' ') + 'was created.';

        AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(c.Id, SupportConstants.TYPE_CASE_CREATED, SupportConstants.OUTCOME_SUCCESS, source);
        entry.requestCategory = result.issueCategory;
        entry.handoffRequired = result.humanHandoffRequired;
        AIInteractionLogService.log(entry);
        return result;
    }

    // ---------------------------------------------------------------------------------------------
    // Status lookup (never authorised by the case number alone)
    // ---------------------------------------------------------------------------------------------

    /**
     * Returns the status of a case the running user can access.
     * @param requireEmailMatch  true for customer-facing channels (agents, Experience Cloud, guest): the supplied
     *                           e-mail must equal the case contact's e-mail. Record sharing is ALWAYS enforced (USER mode).
     * The same message is returned for "not found", "no access" and "e-mail mismatch" so case numbers cannot be probed.
     */
    public static StatusResult getCaseStatus(String caseNumber, String verifiedEmail, Boolean requireEmailMatch, String source) {
        StatusResult result = new StatusResult();
        result.message = 'No matching case was found. Check the details or ask for human support.';
        if (String.isBlank(caseNumber) || caseNumber.length() > 30 || !Pattern.matches('[0-9A-Za-z\\-]+', caseNumber.trim())) {
            return result;
        }
        if (requireEmailMatch == true && String.isBlank(verifiedEmail)) {
            result.message = 'To check a case I need the e-mail address of the contact on the case.';
            return result;
        }

        String lookupNumber = caseNumber.trim();
        Case c = null;
        try {
            List<Case> rows = [
                SELECT Id, CaseNumber, Subject, Status, Priority, LastModifiedDate, IsEscalated,
                       Human_Handoff_Required__c, Contact.Email
                FROM Case
                WHERE CaseNumber = :lookupNumber
                WITH USER_MODE
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                c = rows[0];
            }
        } catch (QueryException e) {
            c = null;
        }

        Boolean verified = c != null;
        if (verified && requireEmailMatch == true) {
            String contactEmail = c.Contact == null ? null : c.Contact.Email;
            verified = String.isNotBlank(contactEmail) && contactEmail.equalsIgnoreCase(verifiedEmail.trim());
        }
        if (!verified) {
            AIInteractionLogService.LogEntry blocked = new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_STATUS, SupportConstants.OUTCOME_BLOCKED, source);
            blocked.errorMessage = 'Status lookup not verified';
            AIInteractionLogService.log(blocked);
            return result;
        }

        result.found = true;
        result.caseId = c.Id;
        result.caseNumber = c.CaseNumber;
        result.subject = c.Subject;
        result.status = c.Status;
        result.priority = c.Priority;
        result.lastUpdated = String.valueOf(c.LastModifiedDate);
        result.humanHandoffRequired = c.Human_Handoff_Required__c == true;
        result.escalated = c.IsEscalated == true;
        result.message = 'Case ' + c.CaseNumber + ' is currently "' + c.Status + '".';

        AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(c.Id, SupportConstants.TYPE_STATUS, SupportConstants.OUTCOME_SUCCESS, source);
        AIInteractionLogService.log(entry);
        return result;
    }

    // ---------------------------------------------------------------------------------------------
    // Comment
    // ---------------------------------------------------------------------------------------------
    public static ActionResult addComment(Id caseId, String body, Boolean isPublic, String source) {
        ActionResult result = new ActionResult();
        result.caseId = caseId;
        if (caseId == null) {
            result.message = 'A case Id is required.';
            return result;
        }
        if (String.isBlank(body)) {
            result.message = 'The comment cannot be empty.';
            return result;
        }
        if (body.length() > SupportConstants.MAX_COMMENT_LENGTH) {
            result.message = 'The comment is too long (maximum ' + SupportConstants.MAX_COMMENT_LENGTH + ' characters).';
            return result;
        }
        try {
            // The comment can only be created when the user can edit/see the parent case (enforced by USER mode).
            List<Case> parent = [SELECT Id FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1];
            if (parent.isEmpty()) {
                result.message = 'Case not found or you do not have access to it.';
                return result;
            }
            CaseComment comment = new CaseComment(ParentId = caseId, CommentBody = body.trim(), IsPublished = isPublic == true);
            Database.insert(comment, AccessLevel.USER_MODE);
        } catch (Exception e) {
            result.message = 'The comment could not be added. You may not have permission.';
            AIInteractionLogService.LogEntry failed = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_COMMENT, SupportConstants.OUTCOME_FAILED, source);
            failed.errorMessage = e.getTypeName();
            AIInteractionLogService.log(failed);
            return result;
        }
        result.success = true;
        result.message = 'The comment was added.';
        AIInteractionLogService.log(new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_COMMENT, SupportConstants.OUTCOME_SUCCESS, source));
        return result;
    }

    // ---------------------------------------------------------------------------------------------
    // Approved field update
    // ---------------------------------------------------------------------------------------------
    public static ActionResult updateApprovedField(Id caseId, String fieldApiName, String newValue) {
        ActionResult result = new ActionResult();
        result.caseId = caseId;
        if (caseId == null || String.isBlank(fieldApiName) || String.isBlank(newValue)) {
            result.message = 'Case Id, field and new value are required.';
            return result;
        }
        if (!APPROVED_FIELDS.contains(fieldApiName)) {
            result.message = 'That field cannot be changed here. Approved fields: ' + String.join(new List<String>(APPROVED_FIELDS), ', ') + '.';
            return result;
        }
        if (!isAllowedPicklistValue(fieldApiName, newValue)) {
            result.message = '"' + newValue + '" is not an active value of ' + fieldApiName + '.';
            return result;
        }
        try {
            List<Case> rows = [SELECT Id FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1];
            if (rows.isEmpty()) {
                result.message = 'Case not found or you do not have access to it.';
                return result;
            }
            Case c = new Case(Id = caseId);
            c.put(fieldApiName, newValue);
            Database.update(c, AccessLevel.USER_MODE);
        } catch (Exception e) {
            result.message = 'The case could not be updated. You may not have permission.';
            return result;
        }
        result.success = true;
        result.message = fieldApiName + ' was updated.';
        return result;
    }

    private static Boolean isAllowedPicklistValue(String fieldApiName, String value) {
        Schema.SObjectField field = Schema.SObjectType.Case.fields.getMap().get(fieldApiName);
        if (field == null) {
            return false;
        }
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }
}
