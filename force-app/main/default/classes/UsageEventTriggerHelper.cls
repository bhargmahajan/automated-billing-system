public with sharing class UsageEventTriggerHelper {
    public static void handleAfterInsert(List<Usage_Event__e> newEvents) {
        if (newEvents == null || newEvents.isEmpty())
            return;

        List<Usage_Record__c> stagingRecords = new List<Usage_Record__c>();

        for (Usage_Event__e evt : newEvents) {
            stagingRecords.add(new Usage_Record__c(
                Account__c          = evt.Account_Id__c,
                Meter_Type__c       = evt.Meter_Type__c,
                Quantity__c         = evt.Quantity__c,
                Idempotency_Hash__c = evt.Idempotency_Hash__c,
                Status__c           = 'PENDING'
            ));
        }

        if (!stagingRecords.isEmpty())
            Database.insert(stagingRecords, false);
    }
}