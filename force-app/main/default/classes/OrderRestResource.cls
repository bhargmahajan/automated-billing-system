@RestResource(urlMapping='/Orders/*')
global with sharing class OrderRestResource {

    global class OrderRequest {
        public Id AccountId;
        public Id ContractId;
        public String ExternalID;
        public Date EffectiveDate;
        public String Status;
        public Decimal TotalAmount;
    }

    global class ResponseWrapper {
        public Integer totalRecordsReceived;
        public Integer totalRecordsSuccess;
        public Integer totalRecordsFailed;
        public List<RecordResult> records;
    }

    global class RecordResult {
        public Integer statusCode;
        public String status;
        public String message;
        public OrderRequest recordData;
    }

    @HttpPost
    global static ResponseWrapper createBulkOrders() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        ResponseWrapper resWrapper = new ResponseWrapper();
        
        List<OrderRequest> incomingOrders;
        try {
            incomingOrders = (List<OrderRequest>) JSON.deserialize(req.requestBody.toString(), List<OrderRequest>.class);
        } catch(Exception e) {
            res.statusCode = 400;
            resWrapper.totalRecordsReceived = 0;
            resWrapper.totalRecordsSuccess = 0;
            resWrapper.totalRecordsFailed = 0;
            resWrapper.records = new List<RecordResult>();
            
            RecordResult parseError = new RecordResult();
            parseError.statusCode = 400;
            parseError.status = 'Fail';
            parseError.message = 'Malformed JSON Payload: ' + e.getMessage();
            resWrapper.records.add(parseError);
            return resWrapper;
        }

        resWrapper.totalRecordsReceived = incomingOrders.size();
        resWrapper.records = new List<RecordResult>();
        
        List<Order> ordersToInsert = new List<Order>();
        integer cnt=0;
        Integer successCount = 0;
        Integer failCount = 0;
        
        for (OrderRequest reqItem : incomingOrders) {
            Order ord = new Order(
                AccountId = reqItem.AccountId,
                ContractId = reqItem.ContractId,
                EffectiveDate = reqItem.EffectiveDate,
                Status = reqItem.Status
            );
            ordersToInsert.add(ord);

            if(cnt==incomingOrders.size() || cnt==10000 || cnt==20000 || cnt==30000 || cnt==40000 || cnt==50000){
                Database.SaveResult[] saveResults = Database.insert(ordersToInsert, false);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    OrderRequest originalRequestData = incomingOrders[i];
                    RecordResult resultItem = new RecordResult();
                    resultItem.recordData = originalRequestData;

                    if (sr.isSuccess()) {
                        successCount++;
                        resultItem.statusCode = 201;
                        resultItem.status = 'Success';
                        resultItem.message = 'Record created successfully. Id: ' + sr.getId();
                    } else {
                        failCount++;
                        resultItem.statusCode = 400;
                        resultItem.status = 'Fail';
                
                        List<String> errorMessages = new List<String>();
                        for (Database.Error err : sr.getErrors()) {
                            errorMessages.add(err.getStatusCode() + ': ' + err.getMessage() + ' (Fields: ' + err.getFields() + ')');
                        }

                        resultItem.message = String.join(errorMessages, ' | ');
                    }
                    
                    resWrapper.records.add(resultItem);
                }
            }
        }

        resWrapper.totalRecordsSuccess = successCount;
        resWrapper.totalRecordsFailed = failCount;

        if (failCount == 0) {
            res.statusCode = 200;
        } else if (successCount > 0) {
            res.statusCode = 206;
        } else {
            res.statusCode = 400;
        }

        return resWrapper;
    }
}