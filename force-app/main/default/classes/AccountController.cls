public with sharing class AccountController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsBatch(Integer limitSize, Integer offset) {
        if (limitSize == null || limitSize <= 0) {
            limitSize = 170;
        }

        if (offset == null || offset <= 0) {
            offset = 0;
        }

        return [
            SELECT Id, Name, AccountNumber, Phone, Type, Industry
            FROM Account
            ORDER BY Name ASC
            LIMIT :limitSize
            OFFSET :offset
        ];
    }
}
