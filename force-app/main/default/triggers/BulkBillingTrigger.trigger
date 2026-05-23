trigger BulkBillingTrigger on Bulk_Billing_Event__e (after insert) {
    List<Id> invoiceIdsToProcess = new List<Id>();
    
    for (Bulk_Billing_Event__e event : Trigger.new) {
        if (event.Billing_Status__c == 'Processing' && event.Invoice_Record_Id__c != null) {
            invoiceIdsToProcess.add((Id)event.Invoice_Record_Id__c);
        }
    }
    
    if (!invoiceIdsToProcess.isEmpty()) {
        System.enqueueJob(new PaymentLink(invoiceIdsToProcess));
    }
}