/**
 * Human handoff and escalation.
 *
 *  - escalate():            manual / agent-requested escalation (USER mode). Idempotent: a case that is already
 *                           flagged for handoff is not changed again, so no second notification is triggered.
 *  - recordFailedAttempt(): increments AI_Failed_Attempts__c. When the configured threshold is reached the Case
 *                           trigger (CaseRoutingRules) escalates the case with reason "Repeated AI Failure".
 *  - notifyEscalations():   sends ONE custom notification per case to the owner (or the queue members). Called by the
 *                           notification Flow, which sets Escalation_Notified__c afterwards; only cases whose
 *                           notification was really sent are reported as sent, so the flag is never set falsely.
 */
public with sharing class SupportEscalationService {
    @TestVisible private static final String NOTIFICATION_TYPE_NAME = 'SmartSupport_Escalation';
    private static final Integer MAX_RECIPIENTS = 100;

    /** Cases whose escalation this transaction logs itself; the Case trigger skips them to avoid a duplicate audit row. */
    private static Set<Id> escalationLoggedByService = new Set<Id>();

    public static Boolean isEscalationLoggedByService(Id caseId) {
        return caseId != null && escalationLoggedByService.contains(caseId);
    }

    public class EscalationResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean alreadyEscalated = false;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String reason;
        @AuraEnabled public String queueName;
        @AuraEnabled public String message;
    }

    public class NotificationResult {
        public Id caseId;
        public Boolean sent = false;
        public String message;
    }

    /** Escalates one case. Never throws; check EscalationResult.success. */
    public static EscalationResult escalate(Id caseId, String reason) {
        return escalate(caseId, reason, SupportConstants.SOURCE_UI);
    }

    public static EscalationResult escalate(Id caseId, String reason, String source) {
        EscalationResult result = new EscalationResult();
        result.caseId = caseId;
        if (caseId == null) {
            result.message = 'A case Id is required.';
            return result;
        }
        String reasonValue = String.isBlank(reason) ? SupportConstants.REASON_MANUAL : reason.trim();
        if (!SupportConstants.VALID_REASONS.contains(reasonValue)) {
            result.message = 'Unsupported escalation reason. Allowed: ' + String.join(new List<String>(SupportConstants.VALID_REASONS), ', ') + '.';
            return result;
        }
        result.reason = reasonValue;

        Case c = loadForEscalation(caseId);
        if (c == null) {
            result.message = 'Case not found or you do not have access to it.';
            AIInteractionLogService.LogEntry blocked = new AIInteractionLogService.LogEntry(null, SupportConstants.TYPE_ESCALATION, SupportConstants.OUTCOME_BLOCKED, source);
            blocked.errorMessage = 'Escalation blocked: case not accessible';
            AIInteractionLogService.log(blocked);
            return result;
        }

        if (c.Human_Handoff_Required__c == true) {
            result.success = true;
            result.alreadyEscalated = true;
            result.message = 'This case is already flagged for human handoff. No new notification was created.';
            return result;
        }

        c.Human_Handoff_Required__c = true;
        c.IsEscalated = true;
        c.Escalation_Notified__c = false;
        if (String.isBlank(c.Escalation_Reason__c)) {
            c.Escalation_Reason__c = reasonValue;
        }
        if (reasonValue == SupportConstants.REASON_SECURITY || reasonValue == SupportConstants.REASON_OUTAGE) {
            c.Priority = SupportConstants.PRIORITY_HIGH;
        }

        String routeKey = routeKeyFor(reasonValue, c.Issue_Category__c);
        Id queueId = QueueRoutingService.resolveOne(routeKey);
        if (queueId == null) {
            queueId = QueueRoutingService.resolveOne(CaseRoutingRules.routeKeyForCategory(c.Issue_Category__c));
        }
        if (queueId != null) {
            c.OwnerId = queueId;
            result.queueName = QueueRoutingService.queueDeveloperName(routeKey);
        }

        escalationLoggedByService.add(caseId);
        try {
            Database.update(c, AccessLevel.USER_MODE);
        } catch (Exception e) {
            escalationLoggedByService.remove(caseId);
            result.message = 'The case could not be escalated. You may not have permission to edit it.';
            AIInteractionLogService.LogEntry failed = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_ESCALATION, SupportConstants.OUTCOME_FAILED, source);
            failed.errorMessage = e.getTypeName();
            AIInteractionLogService.log(failed);
            return result;
        }

        AIInteractionLogService.LogEntry entry = new AIInteractionLogService.LogEntry(caseId, SupportConstants.TYPE_ESCALATION, SupportConstants.OUTCOME_ESCALATED, source);
        entry.requestCategory = c.Issue_Category__c;
        entry.handoffRequired = true;
        entry.recommendedAction = 'Escalated: ' + reasonValue;
        AIInteractionLogService.log(entry);

        result.success = true;
        result.message = 'The case was escalated to a human agent (' + reasonValue + ').';
        return result;
    }

    /** Asks for a human on the customer's behalf (reason: Customer Requested Human). */
    public static EscalationResult requestHuman(Id caseId, String source) {
        return escalate(caseId, SupportConstants.REASON_HUMAN, source);
    }

    /** Increments AI_Failed_Attempts__c. Returns the new count, or null when the case is not accessible/editable. */
    public static Integer recordFailedAttempt(Id caseId) {
        if (caseId == null) {
            return null;
        }
        try {
            List<Case> rows = [SELECT Id, AI_Failed_Attempts__c FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1];
            if (rows.isEmpty()) {
                return null;
            }
            Integer next = (rows[0].AI_Failed_Attempts__c == null ? 0 : rows[0].AI_Failed_Attempts__c.intValue()) + 1;
            rows[0].AI_Failed_Attempts__c = next;
            Database.update(rows[0], AccessLevel.USER_MODE);
            return next;
        } catch (Exception e) {
            return null;
        }
    }

    /** Sends the escalation notification for each case. Bulk safe (fixed number of queries). Never throws. */
    public static List<NotificationResult> notifyEscalations(List<Id> caseIds) {
        List<NotificationResult> results = new List<NotificationResult>();
        if (caseIds == null || caseIds.isEmpty()) {
            return results;
        }

        Map<Id, Case> cases = new Map<Id, Case>([
            SELECT Id, CaseNumber, Subject, OwnerId, Priority, Escalation_Reason__c, Human_Handoff_Required__c, Escalation_Notified__c
            FROM Case
            WHERE Id IN :caseIds
            WITH SYSTEM_MODE
        ]);

        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE_NAME LIMIT 1];
        Id typeId = types.isEmpty() ? null : types[0].Id;

        Set<Id> queueOwners = new Set<Id>();
        for (Case c : cases.values()) {
            if (QueueRoutingService.isQueueId(c.OwnerId)) {
                queueOwners.add(c.OwnerId);
            }
        }
        Map<Id, Set<String>> queueMembers = new Map<Id, Set<String>>();
        if (!queueOwners.isEmpty()) {
            for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE GroupId IN :queueOwners]) {
                if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                    if (!queueMembers.containsKey(gm.GroupId)) {
                        queueMembers.put(gm.GroupId, new Set<String>());
                    }
                    queueMembers.get(gm.GroupId).add(String.valueOf(gm.UserOrGroupId));
                }
            }
        }

        for (Id caseId : caseIds) {
            NotificationResult nr = new NotificationResult();
            nr.caseId = caseId;
            Case c = cases.get(caseId);
            if (c == null) {
                nr.message = 'Case not found.';
            } else if (c.Escalation_Notified__c == true) {
                nr.message = 'Already notified; skipped to prevent a duplicate notification.';
            } else if (typeId == null) {
                nr.message = 'Custom notification type ' + NOTIFICATION_TYPE_NAME + ' is not deployed.';
            } else {
                Set<String> recipients = recipientsFor(c, queueMembers);
                if (recipients.isEmpty()) {
                    nr.message = 'No user recipients could be determined (empty queue?).';
                } else {
                    nr = send(c, typeId, recipients);
                }
            }
            results.add(nr);
        }
        return results;
    }

    private static NotificationResult send(Case c, Id typeId, Set<String> recipients) {
        NotificationResult nr = new NotificationResult();
        nr.caseId = c.Id;
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(typeId);
            notification.setTargetId(c.Id);
            notification.setTitle('Case ' + c.CaseNumber + ' needs a human');
            String reason = String.isBlank(c.Escalation_Reason__c) ? 'Escalation' : c.Escalation_Reason__c;
            notification.setBody(reason + ' - priority ' + (c.Priority == null ? 'not set' : c.Priority) + '.');
            notification.send(recipients);
            nr.sent = true;
            nr.message = 'Notification sent to ' + recipients.size() + ' recipient(s).';
        } catch (Exception e) {
            nr.sent = false;
            nr.message = 'Notification could not be sent: ' + e.getTypeName();
        }
        return nr;
    }

    private static Set<String> recipientsFor(Case c, Map<Id, Set<String>> queueMembers) {
        Set<String> recipients = new Set<String>();
        if (QueueRoutingService.isQueueId(c.OwnerId)) {
            Set<String> members = queueMembers.get(c.OwnerId);
            if (members != null) {
                for (String member : members) {
                    recipients.add(member);
                    if (recipients.size() >= MAX_RECIPIENTS) {
                        break;
                    }
                }
            }
        } else {
            recipients.add(String.valueOf(c.OwnerId));
        }
        return recipients;
    }

    private static String routeKeyFor(String reason, String category) {
        if (reason == SupportConstants.REASON_SECURITY) {
            return SupportConstants.ROUTE_SECURITY;
        }
        if (reason == SupportConstants.REASON_OUTAGE || reason == SupportConstants.REASON_PREMIUM) {
            return SupportConstants.ROUTE_URGENT;
        }
        return CaseRoutingRules.routeKeyForCategory(category);
    }

    private static Case loadForEscalation(Id caseId) {
        try {
            List<Case> rows = [
                SELECT Id, Priority, OwnerId, Issue_Category__c, Human_Handoff_Required__c, Escalation_Reason__c,
                       Escalation_Notified__c, IsEscalated
                FROM Case
                WHERE Id = :caseId
                WITH USER_MODE
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        } catch (QueryException e) {
            return null;
        }
    }
}
