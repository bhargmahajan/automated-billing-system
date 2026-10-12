public with sharing class AutomatedTaxEngine {
    public static Map<Id, Decimal> calculateBulkTax(Map<Id, Account> accountMap, Map<Id, Decimal> taxableAmounts) {
        Map<Id, Decimal> calculatedTaxes = new Map<Id, Decimal>();
        List<Tax_Rate_Rule__mdt> allRules = Tax_Rate_Rule__mdt.getAll().values();

        Map<String, Decimal> ruleMatrix = new Map<String, Decimal>();
        for (Tax_Rate_Rule__mdt rule : allRules) {
            String key = (rule.Country_Code__c + '_' + rule.State_Province__c).toUpperCase();
            ruleMatrix.put(key, rule.Tax_Percentage__c);
        }

        for (Id accId : accountMap.keySet()) {
            Account acc = accountMap.get(accId);
            Decimal taxableAmount = taxableAmounts.containsKey(accId) ? taxableAmounts.get(accId) : 0.00;

            if (taxableAmount <= 0) {
                calculatedTaxes.put(accId, 0.00);
                continue;
            }

            String country = String.isNotBlank(acc.BillingCountryCode) ? acc.BillingCountryCode.toUpperCase() : 'US';
            String state = String.isNotBlank(acc.BillingStateCode) ? acc.BillingStateCode.toUpperCase() : '*';

            Decimal taxRate = 0.00;
            if (ruleMatrix.containsKey(country + '_' + state)) {
                taxRate = ruleMatrix.get(country + '_' + state);
            } else if (ruleMatrix.containsKey(country + '_*')) {
                taxRate = ruleMatrix.get(country + '_*');
            }

            Decimal taxAmount = (taxableAmount * (taxRate / 100.0)).setScale(2, System.RoundingMode.HALF_UP);
            calculatedTaxes.put(accId, taxAmount);
        }

        return calculatedTaxes;
    }
}