/** Test-only data builders. Tests create ALL their data here and never depend on records already in the org. */
@IsTest
public class SupportTestDataFactory {
    public static final String QUEUE_PREFIX = 'SS_Test_';

    public static Account createAccount(String name, String tier) {
        Account a = new Account(Name = name, Support_Tier__c = tier);
        insert a;
        return a;
    }

    public static Contact createContact(Id accountId, String lastName, String email) {
        Contact c = new Contact(AccountId = accountId, LastName = lastName, Email = email);
        insert c;
        return c;
    }

    /**
     * A System Administrator-profile user (sees all records) who has been assigned SmartSupport_Admin. Tests run inside
     * System.runAs(supportUser()): the services use USER mode, and permission set changes only take effect for the
     * running user inside a runAs block. A new unrelated admin who has not yet been assigned the permission set would
     * otherwise be denied field-level access to the custom fields.
     */
    public static User supportUser() {
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = 'SmartSupport_Admin' LIMIT 1];
        User u = new User(
            Alias = 'sssup',
            Email = 'ss.support.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SupportUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'ss.support.' + unique + '@example.com.smartsupport'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            if (!sets.isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = sets[0].Id);
            }
        }
        return u;
    }

    public static Case buildCase(String subject, String description) {
        return new Case(Subject = subject, Description = description);
    }

    public static Case createCase(String subject, String description) {
        Case c = buildCase(subject, description);
        insert c;
        return c;
    }

    /** Re-reads the fields the tests assert on. */
    public static Case reload(Id caseId) {
        return [
            SELECT Id, CaseNumber, Subject, Description, Status, Priority, OwnerId, AccountId, IsEscalated,
                   Issue_Category__c, Sentiment__c, AI_Summary__c, AI_Recommended_Priority__c, AI_Recommended_Action__c,
                   Human_Handoff_Required__c, Escalation_Reason__c, Escalation_Notified__c, Intake_Processed__c,
                   AI_Failed_Attempts__c
            FROM Case
            WHERE Id = :caseId
        ];
    }

    /**
     * Creates one Case queue per routing key and points QueueRoutingService at them (no reliance on org metadata).
     * @return routing key -> queue Id
     */
    public static Map<String, Id> createQueuesAndMapping() {
        Map<String, String> developerNameByKey = new Map<String, String>{
            SupportConstants.ROUTE_BILLING => QUEUE_PREFIX + 'Billing',
            SupportConstants.ROUTE_TECHNICAL => QUEUE_PREFIX + 'Technical',
            SupportConstants.ROUTE_ACCESS => QUEUE_PREFIX + 'Access',
            SupportConstants.ROUTE_SECURITY => QUEUE_PREFIX + 'Security',
            SupportConstants.ROUTE_SHIPPING => QUEUE_PREFIX + 'Shipping',
            SupportConstants.ROUTE_PRODUCT => QUEUE_PREFIX + 'Product',
            SupportConstants.ROUTE_GENERAL => QUEUE_PREFIX + 'General',
            SupportConstants.ROUTE_URGENT => QUEUE_PREFIX + 'Urgent'
        };
        Map<String, Id> queueIdByKey = new Map<String, Id>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Group> groups = new List<Group>();
            for (String key : developerNameByKey.keySet()) {
                String name = developerNameByKey.get(key);
                groups.add(new Group(Name = name, DeveloperName = name, Type = 'Queue'));
            }
            insert groups;
            List<QueueSobject> supported = new List<QueueSobject>();
            for (Group g : groups) {
                supported.add(new QueueSobject(QueueId = g.Id, SobjectType = 'Case'));
            }
            insert supported;
            for (String key : developerNameByKey.keySet()) {
                for (Group g : groups) {
                    if (g.DeveloperName == developerNameByKey.get(key)) {
                        queueIdByKey.put(key, g.Id);
                    }
                }
            }
        }
        QueueRoutingService.mappingOverride = developerNameByKey;
        return queueIdByKey;
    }

    /** A user with no access to Case (or null when the "Minimum Access - Salesforce" profile does not exist in the org). */
    public static User createNoAccessUser() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        if (profiles.isEmpty()) {
            return null;
        }
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User u = new User(
            Alias = 'ssnoacc',
            Email = 'ss.noaccess.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoAccess',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profiles[0].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'ss.noaccess.' + unique + '@example.com.smartsupport'
        );
        // Own runAs block so the setup-object insert never mixes with non-setup DML (MIXED_DML_OPERATION).
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }
}
