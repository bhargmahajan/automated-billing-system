public with sharing class StripePaymentBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    
    private List<Id> invoiceIds;

    public StripePaymentBatch(List<Id> invoiceIds) {
        this.invoiceIds = invoiceIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query the invoices that were successfully created in the REST API
        return Database.getQueryLocator([
            SELECT Id, External_ID__c, Amount_Generated__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Invoice__c> scope) {
        List<Payment__c> newPayments = new List<Payment__c>();
        List<Invoice__c> invoicesToLink = new List<Invoice__c>();

        for (Invoice__c inv : scope) {
            // Ensure amount is strictly greater than 0 before calling Stripe
            if (inv.Amount_Generated__c != null && inv.Amount_Generated__c > 0) {
                String paymentUrl = createStripeCheckoutSession(inv);

                if (paymentUrl != null) {
                    // Initialize the Payment record
                    Payment__c pay = new Payment__c(
                        Amount__c = inv.Amount_Generated__c,
                        Payment_Link__c = paymentUrl,
                        Status__c = 'Pending'
                    );
                    newPayments.add(pay);
                    invoicesToLink.add(inv);
                }
            }
        }

        // Insert Payments and create Junction Records
        if (!newPayments.isEmpty()) {
            insert newPayments;
            
            List<Payment_line_item__c> junctionItemsToInsert = new List<Payment_line_item__c>();

            for (Integer i = 0; i < newPayments.size(); i++) {
                Payment_line_item__c junctionItem = new Payment_line_item__c(
                    Payment__c = newPayments[i].Id,
                    Invoice__c = invoicesToLink[i].Id
                );
                junctionItemsToInsert.add(junctionItem);
            }

            insert junctionItemsToInsert;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Optional: Send an email summary of failures or success, or trigger notifications
    }

    private String createStripeCheckoutSession(Invoice__c inv) {
        String endpoint = 'https://api.stripe.com/v1/checkout/sessions';
        
        // Stripe expects amounts in cents for USD
        Long amountInCents = (Long)(inv.Amount_Generated__c * 100);
        String invName = inv.External_ID__c != null ? inv.External_ID__c : 'Invoice ' + inv.Id;

        // Construct URL Encoded Body
        String body = 'success_url=https://your-domain.com/success' +
            '&cancel_url=https://your-domain.com/cancel' +
            '&mode=payment' +
            '&line_items[0][quantity]=1' +
            '&line_items[0][price_data][currency]=usd' +
            '&line_items[0][price_data][unit_amount]=' + amountInCents +
            '&line_items[0][price_data][product_data][name]=' + EncodingUtil.urlEncode(invName, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        // Ideally, store the Stripe Secret Key in Named Credentials or Custom Metadata Types
        req.setHeader('Authorization', 'Bearer sk_test_YOUR_STRIPE_SECRET_KEY'); 
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) responseMap.get('url');
        }
        
        System.debug('Stripe Callout Failed: ' + res.getBody());
        return null;
    }
}