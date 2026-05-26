@RestResource(urlMapping='/Invoices/*')
global with sharing class InvoiceRestResource {

    global class InvoiceRequest {
        public Id AccountId;
        public String ExternalID;
        public String CouponCode;
        public Decimal DiscountPercentage;
        public String Status;
        public Decimal GeneratedAmount;
        public List<OrderRequest> Orders;
    }

    global class OrderRequest {
        public String ExternalId;
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
        public InvoiceRequest recordData;
    }

    @HttpPost
    global static ResponseWrapper createBulkInvoices() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        ResponseWrapper resWrapper = new ResponseWrapper();
        
        List<InvoiceRequest> incomingRequests;
        try {
            incomingRequests = (List<InvoiceRequest>) JSON.deserialize(req.requestBody.toString(), List<InvoiceRequest>.class);
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

        resWrapper.totalRecordsReceived = incomingRequests.size();
        resWrapper.records = new List<RecordResult>();
        
        Integer successCount = 0;
        Integer failCount = 0;
        
        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        List<InvoiceRequest> validRequests = new List<InvoiceRequest>();
        List<RecordResult> validResults = new List<RecordResult>();
        List<Order_Invoice__c> orderItemsToInsert = new List<Order_Invoice__c>();

        for (InvoiceRequest reqItem : incomingRequests) {
            RecordResult resultItem = new RecordResult();
            resultItem.recordData = reqItem;
            
            Decimal generatedAmount = reqItem.GeneratedAmount;
            Decimal finalAmount = generatedAmount;

            if (reqItem.DiscountPercentage != null && reqItem.DiscountPercentage > 0) {
                Decimal discountAmount = (generatedAmount * reqItem.DiscountPercentage) / 100;
                finalAmount = generatedAmount - discountAmount;
                if (finalAmount < 0) {
                    finalAmount = 0;
                }
            }

            Invoice__c inv = new Invoice__c(
                Account__c = reqItem.AccountId,
                External_ID__c = reqItem.ExternalID,
                Coupon_Code__c = reqItem.CouponCode,
                Status__c = reqItem.Status,
                Amount_Generated__c = generatedAmount,
                Final_Amount__c = finalAmount
            );
            invoicesToInsert.add(inv);
            validRequests.add(reqItem);
            validResults.add(resultItem);
        }

        if (!invoicesToInsert.isEmpty()) {
            // Allow partial success
            Database.SaveResult[] saveResults = Database.insert(invoicesToInsert, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                InvoiceRequest originalRequestData = validRequests[i];
                RecordResult resultItem = validResults[i];

                if (sr.isSuccess()) {
                    successCount++;
                    resultItem.statusCode = 201;
                    resultItem.status = 'Success';
                    resultItem.message = 'Invoice created successfully. Id: ' + sr.getId();

                    // 2. Prepare child Order Invoice Items for successfully created Invoices
                    if (originalRequestData.Orders != null && !originalRequestData.Orders.isEmpty()) {
                        for (OrderRequest ordReq : originalRequestData.Orders) {
                            Order_Invoice__c item = new Order_Invoice__c(
                                Invoice__c = sr.getId(),
                                Order__c = ordReq.ExternalId
                            );
                            orderItemsToInsert.add(item);
                        }
                    }
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

            // 3. Insert child Order Invoice Items if any are present
            if (!orderItemsToInsert.isEmpty()) {
                Database.insert(orderItemsToInsert, false);
            }
        }

        

        resWrapper.totalRecordsSuccess = successCount;
        resWrapper.totalRecordsFailed = failCount;

        // Set appropriate HTTP status codes based on success/failures
        if (failCount == 0 && successCount > 0) {
            res.statusCode = 201; // Created
        } else if (successCount > 0) {
            res.statusCode = 207; // Multi-Status (Partial Success)
        } else {
            res.statusCode = 400; // Bad Request
        }

        return resWrapper;
    }
}