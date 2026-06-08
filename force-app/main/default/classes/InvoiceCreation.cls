public class InvoiceCreation implements Database.Batchable<sObject> {
        public Database.QueryLocator start(Database.BatchableContext bc) {
            return Database.getQueryLocator([
                SELECT Id, AccountId, TotalAmount 
                FROM Order 
                WHERE Status = 'Activated' /* AND Invoice_Created__c = false */
            ]);
        }

        public void execute(Database.BatchableContext bc, List<Order> scope) {
        }

        public void finish(Database.BatchableContext bc) {
        }
}