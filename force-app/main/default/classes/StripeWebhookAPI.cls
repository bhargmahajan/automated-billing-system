@RestResource(urlMapping='/api/stripe/webhook/v1/*')
global without sharing class StripeWebhookAPI {
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String sigHeader = req.headers.get('Stripe-Signature');
        String payload = req.requestBody.toString();
        String webhookSecret = 'whsec_placeholder_secret_key';

        if (!StripeWebhookVerifier.verifySignature(payload, sigHeader, webhookSecret)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"error":"Invalid Signature"}');
            return;
        }

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(payload);
        if ((String) data.get('type') == 'checkout.session.completed') {
            Map<String, Object> session = (Map<String, Object>) ((Map<String, Object>) data.get('data')).get('object');
            String sessionId = (String) session.get('id');
            String paymentIntentId = (String) session.get('payment_intent');
            Decimal amountTotal = ((Decimal) session.get('amount_total')) / 100.0;

            List<Invoice__c> invoices = [SELECT Id, Account__c FROM Invoice__c WHERE Stripe_Session_Id__c = :sessionId LIMIT 1];
            if (!invoices.isEmpty()) {
                Invoice__c inv = invoices[0];
                inv.Status__c = 'PAID';
                update inv;

                insert new Payment_Transaction__c(
                    Invoice__c = inv.Id,
                    Stripe_Payment_Intent_Id__c = paymentIntentId,
                    Amount_Received__c = amountTotal,
                    Status__c = 'SUCCEEDED',
                    HMAC_Signature_Verified__c = true,
                    Raw_Webhook_Payload__c = payload
                );

                insert new Billing_Ledger_Entry__c(
                    Account__c = inv.Account__c,
                    Entry_Type__c = 'PAYMENT_REMITTANCE',
                    Amount__c = -amountTotal,
                    Loyalty_Points_Delta__c = 0,
                    Transaction_Timestamp__c = DateTime.now(),
                    Reference_Id__c = paymentIntentId
                );
            }
        }
        res.statusCode = 200;
        res.responseBody = Blob.valueOf('{"status":"success"}');
    }
}