/** The single Case trigger. All logic lives in CaseTriggerHandler and the services it calls. */
trigger CaseTrigger on Case (before insert, before update, after insert, after update) {
    CaseTriggerHandler.run(Trigger.operationType, Trigger.new, Trigger.oldMap);
}
