trigger UsageEventTrigger on Usage_Event__e (after insert) {
    UsageEventTriggerHelper.handleAfterInsert(Trigger.new);
}
