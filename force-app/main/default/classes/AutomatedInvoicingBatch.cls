public with sharing class AutomatedInvoicingBatch implements Database.Batchable<sObject> {
    private static final Decimal POINT_CASH_VALUE = 0.01;
    private static final Decimal MAX_DISCOUNT_PERCENT = 0.30;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, BillingCountryCode, BillingStateCode,
                (SELECT Id, Amount__c FROM Billing_Ledger_Entries__r 
                 WHERE Entry_Type__c = 'USAGE_CHARGE' AND Reference_Id__c LIKE 'USAGE_%')
            FROM Account
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Map<Id, Account> accountMap = new Map<Id, Account>(scope);
        Set<Id> accountIds = accountMap.keySet();

        Map<Id, Integer> loyaltyBalances = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Account__c accId, SUM(Loyalty_Points_Delta__c) netPoints 
            FROM Billing_Ledger_Entry__c 
            WHERE Account__c IN :accountIds 
            GROUP BY Account__c
        ]) {
            Decimal bal = (Decimal) ar.get('netPoints');
            loyaltyBalances.put((Id) ar.get('accId'), bal != null ? bal.intValue() : 0);
        }

        Map<Id, Decimal> subtotals = new Map<Id, Decimal>();
        Map<Id, Decimal> discounts = new Map<Id, Decimal>();
        Map<Id, Integer> pointsToBurn = new Map<Id, Integer>();
        Map<Id, Decimal> taxableBases = new Map<Id, Decimal>();

        for (Account acc : scope) {
            Decimal subtotal = 0.00;
            for (Billing_Ledger_Entry__c entry : acc.Billing_Ledger_Entries__r) {
                subtotal += entry.Amount__c;
            }
            if (subtotal <= 0) continue;

            subtotals.put(acc.Id, subtotal);
            Integer points = loyaltyBalances.containsKey(acc.Id) ? loyaltyBalances.get(acc.Id) : 0;
            Decimal maxDisc = subtotal * MAX_DISCOUNT_PERCENT;
            Decimal discVal = Math.min(maxDisc, points * POINT_CASH_VALUE);
            Integer burn = (Integer) Math.ceil(discVal / POINT_CASH_VALUE);

            discounts.put(acc.Id, discVal);
            pointsToBurn.put(acc.Id, burn);
            taxableBases.put(acc.Id, subtotal - discVal);
        }

        if (taxableBases.isEmpty()) return;

        Map<Id, Decimal> calculatedTaxes = AutomatedTaxEngine.calculateBulkTax(accountMap, taxableBases);

        List<Invoice__c> invoices = new List<Invoice__c>();
        List<Billing_Ledger_Entry__c> ledgerEntries = new List<Billing_Ledger_Entry__c>();

        for (Id accId : taxableBases.keySet()) {
            Decimal sub = subtotals.get(accId);
            Decimal disc = discounts.get(accId);
            Decimal tax = calculatedTaxes.get(accId);

            invoices.add(new Invoice__c(
                Account__c = accId,
                Status__c = 'POSTED',
                Subtotal__c = sub,
                Loyalty_Discount__c = disc,
                Tax_Amount__c = tax
            ));

            if (pointsToBurn.get(accId) > 0) {
                ledgerEntries.add(new Billing_Ledger_Entry__c(
                    Account__c = accId,
                    Entry_Type__c = 'LOYALTY_REDEEMED',
                    Amount__c = -disc,
                    Loyalty_Points_Delta__c = -pointsToBurn.get(accId),
                    Transaction_Timestamp__c = DateTime.now(),
                    Reference_Id__c = 'REDEEM_' + accId + '_' + DateTime.now().getTime()
                ));
            }

            if (tax > 0) {
                ledgerEntries.add(new Billing_Ledger_Entry__c(
                    Account__c = accId,
                    Entry_Type__c = 'TAX_LIABILITY',
                    Amount__c = tax,
                    Loyalty_Points_Delta__c = 0,
                    Transaction_Timestamp__c = DateTime.now(),
                    Reference_Id__c = 'TAX_' + accId + '_' + DateTime.now().getTime()
                ));
            }
        }

        if (!invoices.isEmpty()) {
            insert invoices;
            if (!ledgerEntries.isEmpty()) insert ledgerEntries;
            System.enqueueJob(new StripePaymentLinkDispatcher(new List<Id>(new Map<Id, Invoice__c>(invoices).keySet())));
        }
    }

    public void finish(Database.BatchableContext bc) {}
}