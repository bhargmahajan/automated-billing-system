public class InvoiceCreation implements Database.Batchable<sObject> {
    List<Billing_Invoice__c> invoicesToCreate = new List<Billing_Invoice__c>();
    private final String query;

    public InvoiceCreation(Set<Id> orderIds) {
        query = 'SELECT Id, AccountId, TotalAmount FROM Order WHERE Id IN :orderIds';
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Order> scope) {
        for(Order ord : scope) {
            Billing_Invoice__c newInvoice = new Billing_Invoice__c(
                    Account__c = ord.AccountId,
                    Order__c = ord.Id,
                    Status__c = 'Draft',
                    Total_Charge_Amount_with_Tax__c = ord.TotalAmount
            );
            invoicesToCreate.add(newInvoice);
        }
    }

    public void finish(Database.BatchableContext bc) {
        Database.insert(invoicesToCreate, true);
    }
}