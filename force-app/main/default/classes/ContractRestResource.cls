@RestResource(urlMapping='/contracts/*')
global with sharing class ContractRestResource {

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
    global static ResponseWrapper createContracts() {
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
            List<Contract> contracts = (List<Contract>) JSON.deserialize(requestBody, List<Contract>.class);
            
            if (contracts == null || contracts.isEmpty()) {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: Contract array is empty.', 0, 0, 0, new List<RecordResult>());
            }

            Integer totalRecords = contracts.size();
            Integer successCount = 0;
            Integer failureCount = 0;
            List<RecordResult> recordResults = new List<RecordResult>();
            
            Database.SaveResult[] results = Database.insert(contracts, false);
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
            String message = isSuccess ? 'All contracts created successfully.' : (successCount > 0 ? 'Partial success: ' + successCount + ' succeeded, ' + failureCount + ' failed.' : 'Failed to create contracts.');
            Integer statusCode = isSuccess ? 201 : (successCount > 0 ? 207 : 400);
            
            res.statusCode = statusCode;
            return new ResponseWrapper(statusCode, isSuccess, message, totalRecords, successCount, failureCount, recordResults);            
        } catch (JSONException e) {
            res.statusCode = 500;
            return new ResponseWrapper(500, false, 'Invalid JSON format: ' + e.getMessage(), 0, 0, 0, new List<RecordResult>());
        } catch (Exception e) {
            res.statusCode = 500;
            return new ResponseWrapper(500, false, 'Internal Server Error: ' + e.getMessage(), 0, 0, 0, new List<RecordResult>());
        }
    }
}