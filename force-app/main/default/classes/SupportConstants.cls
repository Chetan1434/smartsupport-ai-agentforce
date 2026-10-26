/**
 * Single source of truth for every picklist value, routing key and status string used by SmartSupport AI.
 * The values MUST match the picklist definitions in force-app/main/default/objects (checked by scripts/validate_project.py).
 */
public with sharing class SupportConstants {
    // Case.Issue_Category__c
    public static final String CAT_BILLING = 'Billing';
    public static final String CAT_TECHNICAL = 'Technical';
    public static final String CAT_ACCESS = 'Account Access';
    public static final String CAT_SECURITY = 'Security';
    public static final String CAT_SHIPPING = 'Shipping';
    public static final String CAT_PRODUCT = 'Product Defect';
    public static final String CAT_GENERAL = 'General';

    // Sentiment__c
    public static final String SENT_POSITIVE = 'Positive';
    public static final String SENT_NEUTRAL = 'Neutral';
    public static final String SENT_NEGATIVE = 'Negative';
    public static final String SENT_UNKNOWN = 'Unknown';

    // Priority (standard Case.Priority and AI_Recommended_Priority__c)
    public static final String PRIORITY_HIGH = 'High';
    public static final String PRIORITY_MEDIUM = 'Medium';
    public static final String PRIORITY_LOW = 'Low';

    // Case.Escalation_Reason__c
    public static final String REASON_SECURITY = 'Security Concern';
    public static final String REASON_OUTAGE = 'Widespread Outage';
    public static final String REASON_HUMAN = 'Customer Requested Human';
    public static final String REASON_AI_FAILURE = 'Repeated AI Failure';
    public static final String REASON_NO_KNOWLEDGE = 'Insufficient Knowledge';
    public static final String REASON_PREMIUM = 'Premium Account High Priority';
    public static final String REASON_MANUAL = 'Manual Escalation';

    // AI_Interaction_Log__c.Interaction_Type__c
    public static final String TYPE_KNOWLEDGE = 'Knowledge Search';
    public static final String TYPE_SUMMARY = 'Summary';
    public static final String TYPE_CLASSIFICATION = 'Classification';
    public static final String TYPE_ESCALATION = 'Escalation';
    public static final String TYPE_HANDOFF = 'Handoff';
    public static final String TYPE_CASE_CREATED = 'Case Created';
    public static final String TYPE_COMMENT = 'Comment Added';
    public static final String TYPE_STATUS = 'Status Lookup';

    // AI_Interaction_Log__c.Outcome__c
    public static final String OUTCOME_SUCCESS = 'Success';
    public static final String OUTCOME_INSUFFICIENT = 'Insufficient Evidence';
    public static final String OUTCOME_ESCALATED = 'Escalated';
    public static final String OUTCOME_FAILED = 'Failed';
    public static final String OUTCOME_BLOCKED = 'Blocked';

    // AI_Interaction_Log__c.Source__c
    public static final String SOURCE_RULES = 'Rules';
    public static final String SOURCE_AGENTFORCE = 'Agentforce';
    public static final String SOURCE_PROMPT = 'Prompt Builder';
    public static final String SOURCE_LLM = 'External LLM';
    public static final String SOURCE_UI = 'User Interface';

    // Queue_Mapping__mdt DeveloperName values (routing keys)
    public static final String ROUTE_BILLING = 'Billing';
    public static final String ROUTE_TECHNICAL = 'Technical';
    public static final String ROUTE_ACCESS = 'Account_Access';
    public static final String ROUTE_SECURITY = 'Security';
    public static final String ROUTE_SHIPPING = 'Shipping';
    public static final String ROUTE_PRODUCT = 'Product_Defect';
    public static final String ROUTE_GENERAL = 'General';
    public static final String ROUTE_URGENT = 'Urgent_Escalation';

    // Knowledge search statuses
    public static final String KB_FOUND = 'FOUND';
    public static final String KB_INSUFFICIENT = 'INSUFFICIENT_EVIDENCE';
    public static final String KB_UNAVAILABLE = 'UNAVAILABLE';
    public static final String KB_INVALID = 'INVALID_INPUT';

    // Limits shared by services
    public static final Integer MAX_SUBJECT_LENGTH = 255;
    public static final Integer MAX_DESCRIPTION_LENGTH = 32000;
    public static final Integer MAX_COMMENT_LENGTH = 4000;
    public static final Integer MAX_QUESTION_LENGTH = 500;

    public static final Set<String> VALID_CATEGORIES = new Set<String>{
        CAT_BILLING, CAT_TECHNICAL, CAT_ACCESS, CAT_SECURITY, CAT_SHIPPING, CAT_PRODUCT, CAT_GENERAL
    };
    public static final Set<String> VALID_SENTIMENTS = new Set<String>{
        SENT_POSITIVE, SENT_NEUTRAL, SENT_NEGATIVE, SENT_UNKNOWN
    };
    public static final Set<String> VALID_PRIORITIES = new Set<String>{
        PRIORITY_HIGH, PRIORITY_MEDIUM, PRIORITY_LOW
    };
    public static final Set<String> VALID_REASONS = new Set<String>{
        REASON_SECURITY, REASON_OUTAGE, REASON_HUMAN, REASON_AI_FAILURE, REASON_NO_KNOWLEDGE, REASON_PREMIUM, REASON_MANUAL
    };
    public static final Set<String> VALID_INTERACTION_TYPES = new Set<String>{
        TYPE_KNOWLEDGE, TYPE_SUMMARY, TYPE_CLASSIFICATION, TYPE_ESCALATION, TYPE_HANDOFF, TYPE_CASE_CREATED, TYPE_COMMENT, TYPE_STATUS
    };
    public static final Set<String> VALID_OUTCOMES = new Set<String>{
        OUTCOME_SUCCESS, OUTCOME_INSUFFICIENT, OUTCOME_ESCALATED, OUTCOME_FAILED, OUTCOME_BLOCKED
    };
    public static final Set<String> VALID_SOURCES = new Set<String>{
        SOURCE_RULES, SOURCE_AGENTFORCE, SOURCE_PROMPT, SOURCE_LLM, SOURCE_UI
    };

    /** Reads the "Default" Support_Setting__mdt record; every getter has a safe fallback when it is missing. */
    public static Support_Setting__mdt settings() {
        return Support_Setting__mdt.getInstance('Default');
    }

    public static Boolean isCaseAutomationEnabled() {
        Support_Setting__mdt s = settings();
        return s == null || s.Case_Automation_Enabled__c == null || s.Case_Automation_Enabled__c;
    }

    public static Integer failedAttemptThreshold() {
        Support_Setting__mdt s = settings();
        Integer value = (s == null || s.Handoff_Failed_Attempt_Threshold__c == null) ? 2 : s.Handoff_Failed_Attempt_Threshold__c.intValue();
        return value < 1 ? 2 : value;
    }

    public static Integer knowledgeMinMatchedTerms() {
        Support_Setting__mdt s = settings();
        Integer value = (s == null || s.Knowledge_Min_Matched_Terms__c == null) ? 1 : s.Knowledge_Min_Matched_Terms__c.intValue();
        return value < 1 ? 1 : value;
    }

    public static Integer knowledgeMaxResults() {
        Support_Setting__mdt s = settings();
        Integer value = (s == null || s.Knowledge_Max_Results__c == null) ? 5 : s.Knowledge_Max_Results__c.intValue();
        return Math.min(Math.max(value, 1), 10);
    }

    public static Boolean isExternalLlmEnabled() {
        Support_Setting__mdt s = settings();
        return s != null && s.External_LLM_Enabled__c == true;
    }

    public static String externalLlmModel() {
        Support_Setting__mdt s = settings();
        return (s == null || String.isBlank(s.External_LLM_Model__c)) ? 'gpt-4o-mini' : s.External_LLM_Model__c;
    }
}
