@RestResource(urlMapping='/orders/*')
global with sharing class OrderRestResource {
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
        global Id orderId;
        global Integer recordIndex;
        global List<String> errors;
        
        global RecordResult(Boolean success, Id orderId, Integer recordIndex, List<String> errors) {
            this.success = success;
            this.orderId = orderId;
            this.recordIndex = recordIndex;
            this.errors = errors;
        }
    }

    @HttpPost
    global static ResponseWrapper createOrders() {
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
            
            Object untypedReq = JSON.deserializeUntyped(requestBody);
            List<Object> rawOrders;
            
            if (untypedReq instanceof List<Object>) {
                rawOrders = (List<Object>) untypedReq;
            } else if (untypedReq instanceof Map<String, Object>) {
                Map<String, Object> reqMap = (Map<String, Object>) untypedReq;
                if (reqMap.containsKey('orders')) {
                    rawOrders = (List<Object>) reqMap.get('orders');
                } else {
                    rawOrders = new List<Object>{ reqMap };
                }
            } else {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: Expected an array or object.', 0, 0, 0, new List<RecordResult>());
            }
            
            if (rawOrders == null || rawOrders.isEmpty()) {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: Order array is empty.', 0, 0, 0, new List<RecordResult>());
            }
            
            List<Order> orders = new List<Order>();
            Map<Integer, List<OrderItem>> orderItemsByOrderIndex = new Map<Integer, List<OrderItem>>();
            
            for (Integer i = 0; i < rawOrders.size(); i++) {
                Map<String, Object> rawOrderMap = (Map<String, Object>) rawOrders[i];
                if (rawOrderMap.containsKey('Order Products')) {
                    List<Object> rawItems = (List<Object>) rawOrderMap.get('Order Products');
                    if (rawItems != null) {
                        String cleanItemsJson = JSON.serialize(rawItems);
                        List<OrderItem> items = (List<OrderItem>) JSON.deserialize(cleanItemsJson, List<OrderItem>.class);
                        orderItemsByOrderIndex.put(i, items);
                    }
                    rawOrderMap.remove('Order Products');
                }
                
                String cleanOrderJson = JSON.serialize(rawOrderMap);
                Order ord = (Order) JSON.deserialize(cleanOrderJson, Order.class);
                orders.add(ord);
            }
            
            Integer totalRecords = orders.size();
            List<RecordResult> recordResults = new List<RecordResult>();
            
            Database.SaveResult[] results = Database.insert(orders, false);
            List<OrderItem> allItemsToInsert = new List<OrderItem>();
            Map<Integer, Integer> itemIndexToOrderIndex = new Map<Integer, Integer>();
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                List<String> errors = new List<String>();
                
                if (sr.isSuccess()) {
                    if (orderItemsByOrderIndex.containsKey(i) && !orderItemsByOrderIndex.get(i).isEmpty()) {
                        for (OrderItem oi : orderItemsByOrderIndex.get(i)) {
                            oi.OrderId = sr.getId();
                            itemIndexToOrderIndex.put(allItemsToInsert.size(), i);
                            allItemsToInsert.add(oi);
                        }
                    }
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        errors.add('Order Error: ' + err.getMessage());
                    }
                }
                
                recordResults.add(new RecordResult(sr.isSuccess(), sr.getId(), i, errors));
            }
            
            if (!allItemsToInsert.isEmpty()) {
                Database.SaveResult[] itemResults = Database.insert(allItemsToInsert, false);
                for (Integer j = 0; j < itemResults.size(); j++) {
                    Database.SaveResult itemSr = itemResults[j];
                    if (!itemSr.isSuccess()) {
                        Integer parentOrderIndex = itemIndexToOrderIndex.get(j);
                        RecordResult rr = recordResults[parentOrderIndex];
                        for (Database.Error err : itemSr.getErrors()) {
                            rr.errors.add('Order Product Error: ' + err.getMessage());
                        }
                        rr.success = false;
                    }
                }
            }
            
            Integer successCount = 0;
            Integer failureCount = 0;
            for (RecordResult rr : recordResults) {
                if (rr.success) {
                    successCount++;
                } else {
                    failureCount++;
                }
            }
            
            Boolean isSuccess = (failureCount == 0);
            String message = isSuccess ? 'All orders created successfully.' : (successCount > 0 ? 'Partial success: ' + successCount + ' succeeded, ' + failureCount + ' failed.' : 'Failed to create orders.');
            Integer statusCode = isSuccess ? 201 : (successCount > 0 ? 207 : 400);
            
            res.statusCode = statusCode;
            return new ResponseWrapper(statusCode, isSuccess, message, totalRecords, successCount, failureCount, recordResults);
            
        } catch (Exception e) {
            res.statusCode = 500;
            return new ResponseWrapper(500, false, 'Internal Server Error: ' + e.getMessage(), 0, 0, 0, new List<RecordResult>());
        }
    }

    @HttpPatch
    global static ResponseWrapper updateOrders() {
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

            // Allow passing the ID directly in the URI (e.g., /services/apexrest/orders/8015...)
            String requestUri = req.requestURI;
            String uriOrderId = '';
            if (requestUri != null) {
                List<String> uriParts = requestUri.split('/');
                if (!uriParts.isEmpty()) {
                    String lastPart = uriParts[uriParts.size() - 1];
                    if (lastPart != 'orders') {
                        uriOrderId = lastPart;
                    }
                }
            }

            String requestBody = req.requestBody.toString();
            Object untypedReq = JSON.deserializeUntyped(requestBody);
            List<Object> rawOrders;
            
            if (untypedReq instanceof List<Object>) {
                rawOrders = (List<Object>) untypedReq;
            } else if (untypedReq instanceof Map<String, Object>) {
                Map<String, Object> reqMap = (Map<String, Object>) untypedReq;
                if (reqMap.containsKey('orders')) {
                    rawOrders = (List<Object>) reqMap.get('orders');
                } else {
                    rawOrders = new List<Object>{ reqMap };
                }
            } else {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: Expected an array or object.', 0, 0, 0, new List<RecordResult>());
            }
            
            if (rawOrders == null || rawOrders.isEmpty()) {
                res.statusCode = 400;
                return new ResponseWrapper(400, false, 'Invalid Request: Order array is empty.', 0, 0, 0, new List<RecordResult>());
            }
            
            List<Order> orders = new List<Order>();
            
            for (Integer i = 0; i < rawOrders.size(); i++) {
                Map<String, Object> rawOrderMap = (Map<String, Object>) rawOrders[i];
                String cleanOrderJson = JSON.serialize(rawOrderMap);
                Order ord = (Order) JSON.deserialize(cleanOrderJson, Order.class);
                
                if (ord.Id == null) {
                    if (String.isNotBlank(uriOrderId) && rawOrders.size() == 1) {
                        ord.Id = uriOrderId;
                    } else {
                        res.statusCode = 400;
                        return new ResponseWrapper(400, false, 'Invalid Request: Order Id is required for update.', 0, 0, 0, new List<RecordResult>());
                    }
                }
                orders.add(ord);
            }
            
            Integer totalRecords = orders.size();
            List<RecordResult> recordResults = new List<RecordResult>();
            
            // Perform bulk safe update
            Database.SaveResult[] results = Database.update(orders, false);
            
            Integer successCount = 0;
            Integer failureCount = 0;
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                List<String> errors = new List<String>();
                
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error err : sr.getErrors()) {
                        errors.add('Update Error: ' + err.getMessage());
                    }
                }
                
                recordResults.add(new RecordResult(sr.isSuccess(), sr.isSuccess() ? sr.getId() : orders[i].Id, i, errors));
            }
            
            Boolean isSuccess = (failureCount == 0);
            String message = isSuccess ? 'All orders updated successfully.' : (successCount > 0 ? 'Partial success: ' + successCount + ' succeeded, ' + failureCount + ' failed.' : 'Failed to update orders.');
            Integer statusCode = isSuccess ? 200 : (successCount > 0 ? 207 : 400);
            
            res.statusCode = statusCode;
            return new ResponseWrapper(statusCode, isSuccess, message, totalRecords, successCount, failureCount, recordResults);
            
        } catch (Exception e) {
            res.statusCode = 500;
            return new ResponseWrapper(500, false, 'Internal Server Error: ' + e.getMessage(), 0, 0, 0, new List<RecordResult>());
        }
    }
}