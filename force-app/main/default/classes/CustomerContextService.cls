/**
 * Supplies minimal customer context to the intelligence layer.
 *
 * - premiumAccountIds(): used by the Case trigger. It runs in SYSTEM mode on purpose, because routing rules must
 *   behave the same no matter which user saved the case. It returns only Ids (no data is shown to the user).
 * - getContext(): used for display. It runs in USER mode, so the caller only sees what their permissions allow.
 *   Data minimization: only account name, tier, contact name and an open-case count are returned.
 */
public with sharing class CustomerContextService {

    public class CustomerContext {
        @AuraEnabled public String accountName;
        @AuraEnabled public String supportTier;
        @AuraEnabled public String contactName;
        @AuraEnabled public Integer openCasesForAccount = 0;
    }

    /** Returns the subset of the given account Ids whose Support_Tier__c is Premium. */
    public static Set<Id> premiumAccountIds(Set<Id> accountIds) {
        Set<Id> premium = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return premium;
        }
        for (Account a : [SELECT Id FROM Account WHERE Id IN :accountIds AND Support_Tier__c = 'Premium' WITH SYSTEM_MODE]) {
            premium.add(a.Id);
        }
        return premium;
    }

    /** Minimal, permission-aware context for one case. Never throws; returns an empty context on any access problem. */
    public static CustomerContext getContext(Id caseId) {
        CustomerContext context = new CustomerContext();
        if (caseId == null) {
            return context;
        }
        try {
            List<Case> cases = [
                SELECT Id, AccountId, Account.Name, Contact.Name
                FROM Case
                WHERE Id = :caseId
                WITH USER_MODE
                LIMIT 1
            ];
            if (cases.isEmpty()) {
                return context;
            }
            Case c = cases[0];
            context.accountName = c.Account != null ? c.Account.Name : null;
            context.contactName = c.Contact != null ? c.Contact.Name : null;
            if (c.AccountId != null) {
                context.openCasesForAccount = [
                    SELECT COUNT()
                    FROM Case
                    WHERE AccountId = :c.AccountId AND IsClosed = false
                    WITH USER_MODE
                ];
                context.supportTier = readSupportTier(c.AccountId);
            }
        } catch (Exception e) {
            // Missing permission on a field or object: return whatever was collected, without leaking details.
            System.debug(LoggingLevel.WARN, 'CustomerContextService.getContext limited by permissions: ' + e.getTypeName());
        }
        return context;
    }

    private static String readSupportTier(Id accountId) {
        try {
            List<Account> accounts = [SELECT Support_Tier__c FROM Account WHERE Id = :accountId WITH USER_MODE LIMIT 1];
            return accounts.isEmpty() ? null : accounts[0].Support_Tier__c;
        } catch (Exception e) {
            return null;
        }
    }
}
