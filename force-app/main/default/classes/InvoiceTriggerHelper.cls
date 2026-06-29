public class InvoiceTriggerHelper {
    public static void handleAfterUpdate(List<Billing_Invoice__c> newInvoices, Map<Id, Order> oldInvoiceMap) {
        Set<Id> invoicesToProcess = new Set<Id>();
        
        for (Billing_Invoice__c newInvoice : newInvoices) {
            Billing_Invoice__c oldInvoice = oldInvoiceMap.get(newOrder.Id);
            
            if (newInvoice.Status == 'Invoiced' && oldInvoice.Status != 'Invoiced') {
                invoicesToProcess.add(newInvoice.Id);
            }
        }
        
        if (!invoicesToProcess.isEmpty()) {
            Database.executeBatch(new InvoiceCreation(invoicesToProcess));
        }
    }
}