public class InvoiceLineCreation implements Database.Batchable<sObject> {
    private final String query;

    public InvoiceLineCreation(Set<Id> invoiceIds) {
        query = 'SELECT Id, (SELECT Id, PricebookEntry.Product2.Name, Quantity, UnitPrice, TotalPrice FROM OrderItems) ' +
                'FROM Order WHERE Id IN (SELECT Order__c FROM Billing_Invoice__c WHERE Id IN :invoiceIds)';
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Order> scope) {
        List<Billing_Invoice_Line__c> linesToCreate = new List<Billing_Invoice_Line__c>();
        // We need to map the Order Id to the Invoice Id
        Map<Id, Id> orderIdToInvoiceIdMap = new Map<Id, Id>();
        for (Billing_Invoice__c inv : [SELECT Id, Order__c FROM Billing_Invoice__c WHERE Order__c IN :scope]) {
            orderIdToInvoiceIdMap.put(inv.Order__c, inv.Id);
        }

        for (Order ord : scope) {
            Id invoiceId = orderIdToInvoiceIdMap.get(ord.Id);
            if (invoiceId != null && ord.OrderItems != null) {
                for (OrderItem item : ord.OrderItems) {
                    linesToCreate.add(new Billing_Invoice_Line__c(
                        Billing_Invoice__c = invoiceId,
                        Product_Name__c = item.PricebookEntry.Product2.Name,
                        Quantity__c = item.Quantity,
                        Unit_Price__c = item.UnitPrice,
                        Total_Price__c = item.TotalPrice
                    ));
                }
            }
        }

        if (!linesToCreate.isEmpty()) {
            insert linesToCreate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Optional: Add logic for post-batch completion, like sending a summary email.
    }
}