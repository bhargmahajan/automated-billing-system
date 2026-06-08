@RestResource(urlMapping='/accounts/*')
global with sharing class AccountRestResource {

    global class ResponseWrapper {
        global Integer statusCode;
        global Boolean success;
        global String message;
        global Integer totalRecords;
        global Integer successCount;
        global Integer failureCount;
        global List<RecordResult> results;
        
        global ResponseWrapper(Integer statusCode, Boolean success, String message, Integer totalRecords, Integer successCount, Integer failureCount, List<RecordResult> results) {
            this.statusCode = statusCode;
            this.success = success;
            this.message = message;
            this.totalRecords = totalRecords;
            this.successCount = successCount;
            this.failureCount = failureCount;
            this.results = results;
        }
    }

    global class RecordResult {
        global Boolean success;
        global Id accountId;
        global Integer recordIndex;
        global List<String> errors;
        
        global RecordResult(Boolean success, Id accountId, Integer recordIndex, List<String> errors) {
            this.success = success;
            this.accountId = accountId;
            this.recordIndex = recordIndex;
            this.errors = errors;
        }
    }

    @HttpPost
    global static ResponseWrapper createAccounts() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            if (req == null || req.requestBody == null) {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: No payload provided.', 0, 0, 0, new List<RecordResult>());
            }

            String requestBody = req.requestBody.toString();
            List<Account> accounts = (List<Account>) JSON.deserialize(requestBody, List<Account>.class);
            
            if (accounts == null || accounts.isEmpty()) {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: Account array is empty.', 0, 0, 0, new List<RecordResult>());
            }
            
            Integer totalRecords = accounts.size();
            Integer successCount = 0;
            Integer failureCount = 0;
            List<RecordResult> recordResults = new List<RecordResult>();
            
            Database.SaveResult[] results = Database.insert(accounts, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                List<String> errors = new List<String>();
                
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error err : sr.getErrors()) {
                        errors.add(err.getMessage());
                    }
                }
                
                recordResults.add(new RecordResult(sr.isSuccess(), sr.getId(), i, errors));
            }
            
            Boolean isSuccess = (failureCount == 0);
            String message = isSuccess ? 'All accounts created successfully.' : (successCount > 0 ? 'Partial success: ' + successCount + ' succeeded, ' + failureCount + ' failed.' : 'Failed to create accounts.');
            Integer statusCode = isSuccess ? 201 : (successCount > 0 ? 207 : 400);
            
            res.statusCode = statusCode;
            return new ResponseWrapper(statusCode, isSuccess, message, totalRecords, successCount, failureCount, recordResults);
            
        } catch (Exception e) {
            res.statusCode = 500;
            return new ResponseWrapper(500, false, 'Internal Server Error: ' + e.getMessage(), 0, 0, 0, new List<RecordResult>());
        }
    }
}