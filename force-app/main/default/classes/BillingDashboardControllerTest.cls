@IsTest
private class BillingDashboardControllerTest {
    @IsTest
    static void testDashboardSummariesAndInvoices() {
        Account account = new Account(Name = 'Dashboard Account');
        insert account;

        Invoice__c outstandingInvoice = new Invoice__c(
            Account__c = account.Id,
            Status__c = 'POSTED',
            Subtotal__c = 100,
            Loyalty_Discount__c = 10,
            Tax_Amount__c = 5
        );
        Invoice__c paidInvoice = new Invoice__c(
            Account__c = account.Id,
            Status__c = 'PAID',
            Subtotal__c = 50,
            Loyalty_Discount__c = 0,
            Tax_Amount__c = 2.5
        );
        insert new List<Invoice__c>{ outstandingInvoice, paidInvoice };

        insert new Payment_Transaction__c(
            Invoice__c = paidInvoice.Id,
            Amount_Received__c = 52.5,
            Status__c = 'SUCCEEDED'
        );
        insert new Usage_Record__c(
            Account__c = account.Id,
            Meter_Type__c = 'API_CALLS',
            Quantity__c = 120,
            Status__c = 'PENDING',
            Idempotency_Hash__c = 'dashboard-usage-1'
        );

        BillingDashboardController.DashboardData dashboard = BillingDashboardController.getDashboard();

        System.assertEquals(2, dashboard.invoiceCount, 'The dashboard should count all visible invoices.');
        System.assertEquals(1, dashboard.paidInvoiceCount, 'The dashboard should count paid invoices.');
        System.assertEquals(95, dashboard.outstandingBalance, 'Outstanding balance should include posted and overdue invoices.');
        System.assertEquals(52.5, dashboard.paymentsReceived, 'The dashboard should total successful payment transactions.');
        System.assertEquals(1, dashboard.pendingUsageCount, 'The dashboard should count pending usage records.');
        System.assertEquals(120, dashboard.pendingUsageQuantity, 'The dashboard should total pending usage quantity.');
        System.assertEquals(2, dashboard.invoices.size(), 'The dashboard should return the recent invoice rows.');
    }

    @IsTest
    static void testPaymentLinkGenerationLocksInvoiceAndUpdatesStatus() {
        Account account = new Account(Name = 'Payment Link Account');
        insert account;

        Invoice__c invoice = new Invoice__c(
            Account__c = account.Id,
            Status__c = 'POSTED',
            Subtotal__c = 100,
            Loyalty_Discount__c = 0,
            Tax_Amount__c = 0
        );
        insert invoice;
        Test.setMock(HttpCalloutMock.class, new StripePaymentLinkMock());

        Test.startTest();
        BillingDashboardController.generatePaymentLink(invoice.Id);

        Invoice__c reservedInvoice = [
            SELECT Payment_Link_Status__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];
        System.assertEquals('GENERATING', reservedInvoice.Payment_Link_Status__c, 'The invoice should be reserved while the asynchronous link request is pending.');

        Boolean duplicateRequestRejected = false;
        try {
            BillingDashboardController.generatePaymentLink(invoice.Id);
        } catch (AuraHandledException expected) {
            duplicateRequestRejected = true;
        }
        System.assertEquals(true, duplicateRequestRejected, 'Concurrent requests should not enqueue a second payment link job.');
        Test.stopTest();

        Invoice__c completedInvoice = [
            SELECT Stripe_Payment_Link__c, Stripe_Session_Id__c, Payment_Link_Status__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];
        System.assertEquals('READY', completedInvoice.Payment_Link_Status__c, 'A successful Stripe response should mark the link ready.');
        System.assertEquals('https://checkout.stripe.com/pay/cs_dashboard_test', completedInvoice.Stripe_Payment_Link__c, 'The payment link should be saved on the invoice.');
        System.assertEquals('cs_dashboard_test', completedInvoice.Stripe_Session_Id__c, 'The Stripe session id should be saved on the invoice.');
    }

    @IsTest
    static void testFailedPaymentLinkCanBeRetried() {
        Account account = new Account(Name = 'Retry Payment Link Account');
        insert account;

        Invoice__c invoice = new Invoice__c(
            Account__c = account.Id,
            Status__c = 'POSTED',
            Subtotal__c = 25,
            Loyalty_Discount__c = 0,
            Tax_Amount__c = 0
        );
        insert invoice;
        Test.setMock(HttpCalloutMock.class, new StripePaymentLinkMock(500));

        Test.startTest();
        BillingDashboardController.generatePaymentLink(invoice.Id);
        Test.stopTest();

        Invoice__c failedInvoice = [
            SELECT Payment_Link_Status__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];
        System.assertEquals('FAILED', failedInvoice.Payment_Link_Status__c, 'A rejected Stripe request should mark generation as failed.');

        BillingDashboardController.DashboardData dashboard = BillingDashboardController.getDashboard();
        for (BillingDashboardController.InvoiceRow row : dashboard.invoices) {
            if (row.id == invoice.Id) {
                System.assertEquals(true, row.canGeneratePaymentLink, 'A failed payment-link request should be retryable.');
                return;
            }
        }
        System.assert(false, 'The invoice should be present in the dashboard after a failed request.');
    }

    private class StripePaymentLinkMock implements HttpCalloutMock {
        private Integer statusCode;

        StripePaymentLinkMock() {
            this(200);
        }

        StripePaymentLinkMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody('{"id":"cs_dashboard_test","url":"https://checkout.stripe.com/pay/cs_dashboard_test"}');
            return response;
        }
    }
}
