public with sharing class AccountController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsBatch(String searchTerm, Integer limitSize, Integer offset) {
        if (limitSize == null || limitSize <= 0) {
            limitSize = 170;
        }

        if (offset == null || offset <= 0) {
            offset = 0;
        }

        // If no search term, return all accounts; otherwise filter by name
        if (String.isBlank(searchTerm)) {
            return [
                SELECT Id, Name, Email__c, Loyalty_Points_Earned__c, Loyalty_Points_Redeemed__c
                FROM Account
                ORDER BY Name ASC
                LIMIT :limitSize
                OFFSET :offset
            ];
        } 
            String searchPattern = '%' + searchTerm + '%';
            return [
                SELECT Id, Name, Email__c, Loyalty_Points_Earned__c, Loyalty_Points_Redeemed__c
                FROM Account
                WHERE Name LIKE :searchPattern
                ORDER BY Name ASC
                LIMIT :limitSize
                OFFSET :offset
            ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getLoyaltySummary(Id accountId) {
        Map<String, Decimal> result = new Map<String, Decimal>{'totalEarned' => 0, 'totalRedeemed' => 0, 'available' => 0};

        if (accountId == null) return result;

        AggregateResult[] earnedAgg = [
            SELECT SUM(Points__c) total
            FROM Loyalty_Ledger__c
            WHERE Account__c = :accountId AND Transaction_Type__c = 'Earn'
        ];

        AggregateResult[] redeemedAgg = [
            SELECT SUM(Points__c) total
            FROM Loyalty_Ledger__c
            WHERE Account__c = :accountId AND Transaction_Type__c = 'Redeem'
        ];

        Decimal totalEarned = 0;
        Decimal totalRedeemed = 0;

        if (earnedAgg.size() > 0 && earnedAgg[0].get('total') != null) {
            totalEarned = (Decimal) earnedAgg[0].get('total');
        }

        if (redeemedAgg.size() > 0 && redeemedAgg[0].get('total') != null) {
            totalRedeemed = (Decimal) redeemedAgg[0].get('total');
        }

        result.put('totalEarned', totalEarned);
        result.put('totalRedeemed', totalRedeemed);
        result.put('available', totalEarned - totalRedeemed);

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Loyalty_Ledger__c> getLoyaltyTransactions(Id accountId, Integer limitSize, Integer offset) {
        if (limitSize == null || limitSize <= 0) {
            limitSize = 170;
        }

        if (offset == null || offset <= 0) {
            offset = 0;
        }

        if (accountId == null) return new List<Loyalty_Ledger__c>();

        return [
            SELECT Id, Points__c, Transaction_Type__c, Description__c, CreatedDate
            FROM Loyalty_Ledger__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
            OFFSET :offset
        ];
    }
}
