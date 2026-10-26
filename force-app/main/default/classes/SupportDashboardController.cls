/** Read-only data for the smartSupportDashboard LWC. Every query runs in USER mode (sharing + CRUD/FLS). */
public with sharing class SupportDashboardController {

    public class CaseRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String priority;
        @AuraEnabled public String status;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String issueCategory;
        @AuraEnabled public Boolean humanHandoffRequired;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime lastModified;
    }

    public class LogRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String interactionType;
        @AuraEnabled public String outcome;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean humanHandoffRequired;
        @AuraEnabled public Datetime createdDate;
    }

    public class CountRow {
        @AuraEnabled public String label;
        @AuraEnabled public Integer total;
    }

    public class DashboardData {
        @AuraEnabled public Integer openCases = 0;
        @AuraEnabled public Integer highPriorityCases = 0;
        @AuraEnabled public Integer humanAttentionCases = 0;
        @AuraEnabled public Integer negativeSentimentCases = 0;
        @AuraEnabled public Integer escalatedCases = 0;
        @AuraEnabled public List<CaseRow> attentionCases = new List<CaseRow>();
        @AuraEnabled public List<CountRow> openByCategory = new List<CountRow>();
        @AuraEnabled public List<LogRow> recentInteractions = new List<LogRow>();
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        try {
            data.openCases = [SELECT COUNT() FROM Case WHERE IsClosed = false WITH USER_MODE];
            data.highPriorityCases = [SELECT COUNT() FROM Case WHERE IsClosed = false AND Priority = 'High' WITH USER_MODE];
            data.humanAttentionCases = [SELECT COUNT() FROM Case WHERE IsClosed = false AND Human_Handoff_Required__c = true WITH USER_MODE];
            data.negativeSentimentCases = [SELECT COUNT() FROM Case WHERE IsClosed = false AND Sentiment__c = 'Negative' WITH USER_MODE];
            data.escalatedCases = [SELECT COUNT() FROM Case WHERE IsClosed = false AND IsEscalated = true WITH USER_MODE];

            for (AggregateResult ar : [
                SELECT Issue_Category__c category, COUNT(Id) total
                FROM Case
                WHERE IsClosed = false
                WITH USER_MODE
                GROUP BY Issue_Category__c
                ORDER BY COUNT(Id) DESC
            ]) {
                CountRow row = new CountRow();
                row.label = ar.get('category') == null ? 'Uncategorized' : String.valueOf(ar.get('category'));
                row.total = Integer.valueOf(ar.get('total'));
                data.openByCategory.add(row);
            }

            for (Case c : [
                SELECT Id, CaseNumber, Subject, Priority, Status, Sentiment__c, Issue_Category__c,
                       Human_Handoff_Required__c, AI_Recommended_Action__c, Owner.Name, LastModifiedDate
                FROM Case
                WHERE IsClosed = false AND (Human_Handoff_Required__c = true OR Priority = 'High')
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ]) {
                CaseRow row = new CaseRow();
                row.id = c.Id;
                row.caseNumber = c.CaseNumber;
                row.subject = c.Subject;
                row.priority = c.Priority;
                row.status = c.Status;
                row.sentiment = c.Sentiment__c;
                row.issueCategory = c.Issue_Category__c;
                row.humanHandoffRequired = c.Human_Handoff_Required__c;
                row.recommendedAction = c.AI_Recommended_Action__c;
                row.ownerName = c.Owner == null ? null : c.Owner.Name;
                row.lastModified = c.LastModifiedDate;
                data.attentionCases.add(row);
            }

            for (AI_Interaction_Log__c log : [
                SELECT Id, Name, Case__c, Case__r.CaseNumber, Interaction_Type__c, Outcome__c, Source__c,
                       Human_Handoff_Required__c, CreatedDate
                FROM AI_Interaction_Log__c
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 10
            ]) {
                LogRow row = new LogRow();
                row.id = log.Id;
                row.name = log.Name;
                row.caseId = log.Case__c;
                row.caseNumber = log.Case__r == null ? null : log.Case__r.CaseNumber;
                row.interactionType = log.Interaction_Type__c;
                row.outcome = log.Outcome__c;
                row.source = log.Source__c;
                row.humanHandoffRequired = log.Human_Handoff_Required__c;
                row.createdDate = log.CreatedDate;
                data.recentInteractions.add(row);
            }
        } catch (Exception e) {
            if (!(e instanceof QueryException || e instanceof SecurityException)) {
                throw e;
            }
            throw auraError('You do not have permission to view all the data on this dashboard. Ask an administrator to assign the SmartSupport Agent permission set.');
        }
        return data;
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
