public class StripePaymentLinkDispatcher implements Queueable, Database.AllowsCallouts {
    private List<Id> invoiceIds;

    public StripePaymentLinkDispatcher(List<Id> invoiceIds) {
        this.invoiceIds = invoiceIds;
    }

    public void execute(QueueableContext context) {
        List<Invoice__c> invoices = [
            SELECT Id, Total_Due__c, Payment_Link_Status__c
            FROM Invoice__c 
            WHERE Id IN :invoiceIds
                AND Stripe_Payment_Link__c = NULL
                AND Payment_Link_Status__c = 'GENERATING'
        ];

        List<Invoice__c> toUpdate = new List<Invoice__c>();

        for (Invoice__c inv : invoices) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Stripe_API/v1/checkout/sessions');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            String idempotencyKey = EncodingUtil.convertToHex(
                Crypto.generateDigest('SHA-256', Blob.valueOf(inv.Id + '_' + inv.Total_Due__c))
            );
            req.setHeader('Idempotency-Key', idempotencyKey);

            Long unitAmount = (Long)(inv.Total_Due__c * 100);
            String body = 'payment_method_types[]=card' +
                          '&mode=payment' +
                          '&success_url=https://yourcompany.my.site.com/success' +
                          '&cancel_url=https://yourcompany.my.site.com/cancel' +
                          '&line_items[0][price_data][currency]=usd' +
                          '&line_items[0][price_data][unit_amount]=' + String.valueOf(unitAmount) +
                          '&line_items[0][price_data][product_data][name]=Invoice+' + inv.Id;
            req.setBody(body);

            HttpResponse res;
            try {
                res = new Http().send(req);
            } catch (CalloutException calloutError) {
                inv.Payment_Link_Status__c = 'FAILED';
                toUpdate.add(inv);
                continue;
            }

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                try {
                    Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String paymentLink = (String) resp.get('url');
                    String sessionId = (String) resp.get('id');
                    if (String.isNotBlank(paymentLink) && String.isNotBlank(sessionId)) {
                        inv.Stripe_Payment_Link__c = paymentLink;
                        inv.Stripe_Session_Id__c = sessionId;
                        inv.Payment_Link_Status__c = 'READY';
                    } else {
                        inv.Payment_Link_Status__c = 'FAILED';
                    }
                } catch (JSONException responseError) {
                    inv.Payment_Link_Status__c = 'FAILED';
                }
            } else {
                inv.Payment_Link_Status__c = 'FAILED';
            }
            toUpdate.add(inv);
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }
}