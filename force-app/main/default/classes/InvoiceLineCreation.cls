public class InvoiceLineCreation implements Database.Batchable<sObject> {
    List<Billing_Invoice_Line__c> linesToCreate = new List<Billing_Invoice_Line__c>();
    private final String query;
    private final Set<Id> invoiceIdsForProcessing;

    public InvoiceLineCreation(Set<Id> invoiceIds) {
        this.invoiceIdsForProcessing = invoiceIds;
        query = 'SELECT Id, (SELECT Id, PricebookEntry.Product2Id, PricebookEntry.Product2.Name, Quantity, UnitPrice, TotalPrice FROM OrderItems) ' +
                'FROM Order WHERE Id IN (SELECT Order__c FROM Billing_Invoice__c WHERE Id IN :invoiceIds)';
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Order> scope) {
        // Map to hold an Order ID and its list of related Invoices
        Map<Id, List<Billing_Invoice__c>> orderToInvoicesMap = new Map<Id, List<Billing_Invoice__c>>();

        // Find all invoices in this batch run that are related to the orders in the current scope
        for (Billing_Invoice__c inv : [SELECT Id, Order__c FROM Billing_Invoice__c WHERE Order__c IN :scope AND Id IN :invoiceIdsForProcessing]) {
            if (!orderToInvoicesMap.containsKey(inv.Order__c)) {
                orderToInvoicesMap.put(inv.Order__c, new List<Billing_Invoice__c>());
            }
            orderToInvoicesMap.get(inv.Order__c).add(inv);
        }

        for (Order ord : scope) {
            List<Billing_Invoice__c> relatedInvoices = orderToInvoicesMap.get(ord.Id);

            if (relatedInvoices != null && !relatedInvoices.isEmpty() && ord.OrderItems != null) {
                // For each invoice related to this order...
                for (Billing_Invoice__c invoice : relatedInvoices) {
                    // ...create a set of invoice lines from the order's products
                    for (OrderItem item : ord.OrderItems) {
                        linesToCreate.add(new Billing_Invoice_Line__c(
                            Invoice__c = invoice.Id,
                            Product__c = item.PricebookEntry.Product2Id,
                            Quantity__c = item.Quantity,
                            Unit_Price__c = item.UnitPrice
                        ));
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!linesToCreate.isEmpty()) {
            Database.insert(linesToCreate, true);
        }
    }
}