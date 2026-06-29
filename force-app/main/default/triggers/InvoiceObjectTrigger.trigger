trigger InvoiceObjectTrigger on Billing_Invoice__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        InvoiceTriggerHelper.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}