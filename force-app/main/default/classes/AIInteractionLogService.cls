/**
 * Writes the AI_Interaction_Log__c audit trail.
 *
 * Declared "without sharing" on purpose: an audit record must be written even when the acting user has no
 * Create permission on the log object (for example a customer-facing agent user). The class only INSERTS
 * records whose fields are restricted picklist values, flags, or sanitized text (emails and long numbers removed,
 * truncated to 255). It never reads data, never stores raw customer messages, and never throws: a failed audit
 * write must not break the business transaction. This is documented in docs/security-review.md.
 */
public without sharing class AIInteractionLogService {
    private static final Pattern EMAIL_PATTERN = Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}');
    private static final Pattern LONG_NUMBER_PATTERN = Pattern.compile('\\d{6,}');

    /** One audit entry. Values are validated against the allowed picklist values before the insert. */
    public class LogEntry {
        public Id caseId;
        public String interactionType;
        public String requestCategory;
        public String suggestedPriority;
        public String sentiment;
        public String recommendedAction;
        public Boolean handoffRequired = false;
        public String outcome;
        public String source;
        public String errorMessage;

        public LogEntry() {
        }

        public LogEntry(Id caseId, String interactionType, String outcome, String source) {
            this.caseId = caseId;
            this.interactionType = interactionType;
            this.outcome = outcome;
            this.source = source;
        }
    }

    /** Builds an entry pre-filled from the persisted AI fields of a case. */
    public static LogEntry fromCase(Case c, String interactionType, String outcome, String source) {
        LogEntry entry = new LogEntry(c.Id, interactionType, outcome, source);
        entry.requestCategory = c.Issue_Category__c;
        entry.suggestedPriority = c.AI_Recommended_Priority__c;
        entry.sentiment = c.Sentiment__c;
        entry.recommendedAction = c.AI_Recommended_Action__c;
        entry.handoffRequired = c.Human_Handoff_Required__c == true;
        return entry;
    }

    /** Convenience overload. */
    public static Integer log(LogEntry entry) {
        return entry == null ? 0 : log(new List<LogEntry>{ entry });
    }

    /** Inserts all valid entries in ONE DML statement. Returns the number of records saved. */
    public static Integer log(List<LogEntry> entries) {
        if (entries == null || entries.isEmpty()) {
            return 0;
        }
        List<AI_Interaction_Log__c> records = new List<AI_Interaction_Log__c>();
        for (LogEntry entry : entries) {
            AI_Interaction_Log__c record = toRecord(entry);
            if (record != null) {
                records.add(record);
            }
        }
        if (records.isEmpty()) {
            return 0;
        }

        Integer saved = 0;
        List<Database.SaveResult> results = Database.insert(records, false);
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                saved++;
            } else {
                // Validation messages contain no customer data; log type only.
                System.debug(LoggingLevel.WARN, 'AI log insert failed: ' + result.getErrors()[0].getStatusCode());
            }
        }
        return saved;
    }

    /** Removes email addresses and long digit runs, collapses whitespace and truncates to maxLength. */
    public static String sanitize(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        String cleaned = scrubPii(value).replaceAll('[\\r\\n\\t]+', ' ').trim();
        Integer maxLen = (maxLength == null || maxLength < 1) ? 255 : maxLength;
        return cleaned.length() > maxLen ? cleaned.substring(0, maxLen) : cleaned;
    }

    /** Replaces e-mail addresses and runs of 6 or more digits (phone, card, account numbers) with placeholders. */
    public static String scrubPii(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String withoutEmail = EMAIL_PATTERN.matcher(text).replaceAll('[email]');
        return LONG_NUMBER_PATTERN.matcher(withoutEmail).replaceAll('[number]');
    }

    private static AI_Interaction_Log__c toRecord(LogEntry entry) {
        if (entry == null || !SupportConstants.VALID_INTERACTION_TYPES.contains(entry.interactionType)) {
            return null; // cannot audit an unknown interaction type
        }
        AI_Interaction_Log__c record = new AI_Interaction_Log__c();
        record.Case__c = entry.caseId;
        record.Interaction_Type__c = entry.interactionType;
        record.Outcome__c = SupportConstants.VALID_OUTCOMES.contains(entry.outcome) ? entry.outcome : SupportConstants.OUTCOME_FAILED;
        record.Source__c = SupportConstants.VALID_SOURCES.contains(entry.source) ? entry.source : SupportConstants.SOURCE_RULES;
        record.Request_Category__c = sanitize(entry.requestCategory, 80);
        record.Suggested_Priority__c = SupportConstants.VALID_PRIORITIES.contains(entry.suggestedPriority) ? entry.suggestedPriority : null;
        record.Sentiment__c = SupportConstants.VALID_SENTIMENTS.contains(entry.sentiment) ? entry.sentiment : null;
        record.Recommended_Action__c = sanitize(entry.recommendedAction, 255);
        record.Human_Handoff_Required__c = entry.handoffRequired == true;
        record.Error_Message__c = sanitize(entry.errorMessage, 255);
        return record;
    }
}
