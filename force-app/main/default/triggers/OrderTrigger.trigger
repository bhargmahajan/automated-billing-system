trigger OrderTrigger on Order (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        OrderTriggerHelper.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}