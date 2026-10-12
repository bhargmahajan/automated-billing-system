public with sharing class UsageRatingEngineBatch implements Database.Batchable<sObject> {
    private IPricingStrategy strategy = new TieredSaaSPricingStrategy();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Account__c, Meter_Type__c, Quantity__c, Status__c 
            FROM Usage_Record__c 
            WHERE Status__c = 'PENDING'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Usage_Record__c> scope) {
        Map<Id, Decimal> accountUsageTotals = new Map<Id, Decimal>();
        List<Billing_Ledger_Entry__c> ledgerEntries = new List<Billing_Ledger_Entry__c>();

        for (Usage_Record__c usage : scope) {
            Decimal charge = strategy.calculateCharge(usage.Meter_Type__c, usage.Quantity__c);
            Decimal currentTotal = accountUsageTotals.containsKey(usage.Account__c) ? accountUsageTotals.get(usage.Account__c) : 0.00;
            accountUsageTotals.put(usage.Account__c, currentTotal + charge);
            usage.Status__c = 'RATED';
        }

        for (Id accId : accountUsageTotals.keySet()) {
            Decimal total = accountUsageTotals.get(accId);
            if (total <= 0) continue;

            Integer pointsEarned = (Integer) Math.floor(total / 10.0);

            ledgerEntries.add(new Billing_Ledger_Entry__c(
                Account__c = accId,
                Entry_Type__c = 'USAGE_CHARGE',
                Amount__c = total,
                Loyalty_Points_Delta__c = 0,
                Transaction_Timestamp__c = DateTime.now(),
                Reference_Id__c = 'USAGE_' + bc.getJobId() + '_' + accId
            ));

            if (pointsEarned > 0) {
                ledgerEntries.add(new Billing_Ledger_Entry__c(
                    Account__c = accId,
                    Entry_Type__c = 'LOYALTY_ACCRUAL',
                    Amount__c = 0.00,
                    Loyalty_Points_Delta__c = pointsEarned,
                    Transaction_Timestamp__c = DateTime.now(),
                    Reference_Id__c = 'ACCRUAL_' + bc.getJobId() + '_' + accId
                ));
            }
        }

        if (!ledgerEntries.isEmpty()) insert ledgerEntries;
        update scope;
    }

    public void finish(Database.BatchableContext bc) {
        Database.executeBatch(new AutomatedInvoicingBatch(), 200);
    }
}