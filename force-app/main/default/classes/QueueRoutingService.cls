/**
 * Resolves routing keys (for example "Billing" or "Urgent_Escalation") to Case queue Ids.
 *
 * Nothing is hard-coded: the key -> queue DeveloperName mapping lives in Queue_Mapping__mdt, so an admin can
 * re-map a queue in Setup. A key is only resolved when ALL of these are true:
 *   1. an active Queue_Mapping__mdt record exists for the key,
 *   2. a queue with that DeveloperName exists in the org,
 *   3. the queue is enabled for the Case object (otherwise assigning the case would fail).
 * Unresolved keys are simply omitted, so callers keep the current owner (safe handling of a missing queue).
 *
 * "inherited sharing": Group and QueueSobject are setup objects that every user can read; the lookup returns only Ids.
 */
public inherited sharing class QueueRoutingService {
    /** Test hook: routing key -> queue DeveloperName. When set, Queue_Mapping__mdt is ignored. */
    @TestVisible private static Map<String, String> mappingOverride;

    /** Bulk lookup: one Group query and one QueueSobject query regardless of how many keys are requested. */
    public static Map<String, Id> resolve(Set<String> routeKeys) {
        Map<String, Id> result = new Map<String, Id>();
        if (routeKeys == null || routeKeys.isEmpty()) {
            return result;
        }

        Map<String, String> queueNameByKey = new Map<String, String>();
        for (String key : routeKeys) {
            String developerName = mappedQueueName(key);
            if (String.isNotBlank(developerName)) {
                queueNameByKey.put(key, developerName);
            }
        }
        if (queueNameByKey.isEmpty()) {
            return result;
        }

        Set<String> queueNames = new Set<String>(queueNameByKey.values());
        Map<String, Id> queueIdByName = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN :queueNames]) {
            queueIdByName.put(g.DeveloperName, g.Id);
        }
        if (queueIdByName.isEmpty()) {
            return result;
        }

        Set<Id> queueIds = new Set<Id>(queueIdByName.values());
        Set<Id> caseEnabledQueueIds = new Set<Id>();
        for (QueueSobject qs : [SELECT QueueId FROM QueueSobject WHERE SobjectType = 'Case' AND QueueId IN :queueIds]) {
            caseEnabledQueueIds.add(qs.QueueId);
        }

        for (String key : queueNameByKey.keySet()) {
            Id queueId = queueIdByName.get(queueNameByKey.get(key));
            if (queueId != null && caseEnabledQueueIds.contains(queueId)) {
                result.put(key, queueId);
            }
        }
        return result;
    }

    /** Convenience wrapper for a single key; returns null when the key cannot be resolved. */
    public static Id resolveOne(String routeKey) {
        if (String.isBlank(routeKey)) {
            return null;
        }
        return resolve(new Set<String>{ routeKey }).get(routeKey);
    }

    /** DeveloperName of the queue mapped to a routing key (active mappings only), or null. Does not check the queue exists. */
    public static String queueDeveloperName(String routeKey) {
        return mappedQueueName(routeKey);
    }

    /** True when the Id belongs to a Group record (queues use the 00G prefix). */
    public static Boolean isQueueId(Id ownerId) {
        return ownerId != null && String.valueOf(ownerId).startsWith('00G');
    }

    private static String mappedQueueName(String routeKey) {
        if (String.isBlank(routeKey)) {
            return null;
        }
        if (mappingOverride != null) {
            return mappingOverride.get(routeKey);
        }
        Queue_Mapping__mdt mapping = Queue_Mapping__mdt.getInstance(routeKey);
        if (mapping == null || mapping.Is_Active__c != true) {
            return null;
        }
        return mapping.Queue_Developer_Name__c;
    }
}
