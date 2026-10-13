@IsTest
private class SaaSBillingProjectTest {
    private static final String WEBHOOK_SECRET = 'whsec_placeholder_secret_key';

    @IsTest
    static void testTieredPricingAndTaxEngine() {
        TieredSaaSPricingStrategy strategy = new TieredSaaSPricingStrategy();

        System.assertEquals(15.00, strategy.calculateCharge('API_CALLS', 25000), 'API call pricing should apply the correct tier rate.');
        System.assertEquals(125.00, strategy.calculateCharge('STORAGE_GB', 2500), 'Storage pricing should match the per-GB rate.');
        System.assertEquals(0.00, strategy.calculateCharge('COMPUTE_HOURS', 0), 'Zero quantity should not generate any charge.');
        System.assertEquals(0.00, strategy.calculateCharge('UNKNOWN', 100), 'Unknown meter types should not be charged.');

        Account acc = new Account(Name = 'Tax Test', BillingCountryCode = 'US', BillingStateCode = 'CA');
        insert acc;

        Map<Id, Account> accountMap = new Map<Id, Account>{ acc.Id => acc };
        Map<Id, Decimal> taxableAmounts = new Map<Id, Decimal>{ acc.Id => 100.00 };

        Map<Id, Decimal> taxes = AutomatedTaxEngine.calculateBulkTax(accountMap, taxableAmounts);
        System.assertEquals(8.25, taxes.get(acc.Id), 'US California tax should be 8.25% on the taxable base.');
    }

    @IsTest
    static void testUsageEventHelperAndRatingEngine() {
        Account acc = new Account(Name = 'Usage Test', BillingCountryCode = 'US', BillingStateCode = 'CA');
        insert acc;

        Usage_Event__e usageEvent = new Usage_Event__e(
            Account_Id__c = acc.Id,
            Meter_Type__c = 'API_CALLS',
            Quantity__c = 25000,
            Idempotency_Hash__c = 'usage-event-hash-1'
        );

        Test.startTest();
        UsageEventTriggerHelper.handleAfterInsert(new List<Usage_Event__e>{ usageEvent });
        Test.stopTest();

        Usage_Record__c usageRecord = [
            SELECT Id, Status__c, Quantity__c, Meter_Type__c, Account__c
            FROM Usage_Record__c
            WHERE Account__c = :acc.Id
            LIMIT 1
        ];

        System.assertEquals('PENDING', usageRecord.Status__c, 'The staged usage record should be created as pending.');

        UsageRatingEngineBatch batch = new UsageRatingEngineBatch();
        batch.execute(null, new List<Usage_Record__c>{ usageRecord });

        Usage_Record__c updatedRecord = [
            SELECT Id, Status__c
            FROM Usage_Record__c
            WHERE Id = :usageRecord.Id
        ];
        System.assertEquals('RATED', updatedRecord.Status__c, 'The usage record should be marked as rated after charge calculation.');

        List<Billing_Ledger_Entry__c> ledgerEntries = [
            SELECT Id, Entry_Type__c, Amount__c
            FROM Billing_Ledger_Entry__c
            WHERE Account__c = :acc.Id
        ];
        System.assertEquals(1, ledgerEntries.size(), 'The rating batch should create a single usage charge ledger entry.');
        System.assertEquals('USAGE_CHARGE', ledgerEntries[0].Entry_Type__c, 'The ledger entry should represent the usage charge.');
        System.assertEquals(15.00, ledgerEntries[0].Amount__c, 'The usage charge should be derived from the pricing strategy.');
    }

    @IsTest
    static void testAutomatedInvoicingBatchAndStripeDispatcher() {
        Test.setMock(HttpCalloutMock.class, new StripePaymentLinkMock());

        Account acc = new Account(Name = 'Invoice Test', BillingCountryCode = 'US', BillingStateCode = 'CA');
        insert acc;

        insert new List<Billing_Ledger_Entry__c>{
            new Billing_Ledger_Entry__c(
                Account__c = acc.Id,
                Entry_Type__c = 'USAGE_CHARGE',
                Amount__c = 100.00,
                Reference_Id__c = 'USAGE_123',
                Transaction_Timestamp__c = DateTime.now()
            ),
            new Billing_Ledger_Entry__c(
                Account__c = acc.Id,
                Entry_Type__c = 'LOYALTY_ACCRUAL',
                Amount__c = 0.00,
                Loyalty_Points_Delta__c = 500,
                Reference_Id__c = 'ACCRUAL_123',
                Transaction_Timestamp__c = DateTime.now()
            )
        };

        Account accountWithLedger = [
            SELECT Id, BillingCountryCode, BillingStateCode,
                (SELECT Id, Account__c, Amount__c, Entry_Type__c, Reference_Id__c, Loyalty_Points_Delta__c
                 FROM Billing_Ledger_Entries__r)
            FROM Account
            WHERE Id = :acc.Id
        ];

        AutomatedInvoicingBatch batch = new AutomatedInvoicingBatch();

        Test.startTest();
        batch.execute(null, new List<Account>{ accountWithLedger });
        Test.stopTest();

        Invoice__c invoice = [
            SELECT Id, Account__c, Status__c, Subtotal__c, Loyalty_Discount__c, Tax_Amount__c,
                Stripe_Payment_Link__c, Stripe_Session_Id__c
            FROM Invoice__c
            WHERE Account__c = :acc.Id
            LIMIT 1
        ];

        System.assertEquals('POSTED', invoice.Status__c, 'The batch should create a posted invoice for taxable usage.');
        System.assertEquals(100.00, invoice.Subtotal__c, 'Subtotal should reflect the usage charge.');
        System.assertEquals(5.00, invoice.Loyalty_Discount__c, 'The loyalty discount should cap the discount based on the available points balance.');
        System.assertEquals(7.84, invoice.Tax_Amount__c, 'Tax should be calculated using the configured state tax rate.');
        System.assertEquals('https://checkout.stripe.com/pay/cs_test_123', invoice.Stripe_Payment_Link__c, 'The queued Stripe payment link dispatch should populate the invoice link.');
        System.assertEquals('cs_test_123', invoice.Stripe_Session_Id__c, 'The Stripe checkout session id should be captured on the invoice.');
    }

    @IsTest
    static void testWebhookVerifierAndApi() {
        User adminUser = createSystemAdminUser();
        System.runAs(adminUser) {
            String payload = JSON.serialize(new Map<String, Object>{
                'type' => 'checkout.session.completed',
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id' => 'cs_test_webhook_123',
                        'payment_intent' => 'pi_test_123',
                        'amount_total' => 15000
                    }
                }
            });

            Long timestamp = DateTime.now().getTime() / 1000;
            Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(timestamp + '.' + payload), Blob.valueOf(WEBHOOK_SECRET));
            String signatureHeader = 't=' + timestamp + ',v1=' + EncodingUtil.convertToHex(hmac);

            System.assertEquals(true, StripeWebhookVerifier.verifySignature(payload, signatureHeader, WEBHOOK_SECRET), 'Valid Stripe signatures should be accepted.');
            System.assertEquals(false, StripeWebhookVerifier.verifySignature(payload, 't=1,v1=bad', WEBHOOK_SECRET), 'Invalid Stripe signatures should be rejected.');

            Account acc = new Account(Name = 'Webhook Test', BillingCountryCode = 'US', BillingStateCode = 'CA');
            insert acc;

            Invoice__c invoice = new Invoice__c(
                Account__c = acc.Id,
                Status__c = 'POSTED',
                Subtotal__c = 150.00,
                Tax_Amount__c = 12.38,
                Stripe_Session_Id__c = 'cs_test_webhook_123'
            );
            insert invoice;

            RestRequest req = new RestRequest();
            req.httpMethod = 'POST';
            req.headers.put('Stripe-Signature', signatureHeader);
            req.requestBody = Blob.valueOf(payload);
            RestContext.request = req;
            RestContext.response = new RestResponse();

            Test.startTest();
            StripeWebhookAPI.handleWebhook();
            Test.stopTest();

            System.assertEquals(200, RestContext.response.statusCode, 'The webhook should acknowledge a valid event.');

            Invoice__c updatedInvoice = [
                SELECT Id, Status__c
                FROM Invoice__c
                WHERE Id = :invoice.Id
            ];
            System.assertEquals('PAID', updatedInvoice.Status__c, 'A completed checkout session should mark the invoice as paid.');

            Payment_Transaction__c paymentTransaction = [
                SELECT Id, Amount_Received__c, Status__c, Stripe_Payment_Intent_Id__c
                FROM Payment_Transaction__c
                WHERE Invoice__c = :invoice.Id
                LIMIT 1
            ];
            System.assertEquals(150.00, paymentTransaction.Amount_Received__c, 'The payment transaction should store the captured amount.');
            System.assertEquals('SUCCEEDED', paymentTransaction.Status__c, 'The payment should be marked as succeeded.');
            System.assertEquals('pi_test_123', paymentTransaction.Stripe_Payment_Intent_Id__c, 'The Stripe payment intent should be persisted.');

            Billing_Ledger_Entry__c ledgerEntry = [
                SELECT Id, Entry_Type__c, Amount__c
                FROM Billing_Ledger_Entry__c
                WHERE Account__c = :acc.Id
                AND Reference_Id__c = 'pi_test_123'
                LIMIT 1
            ];
            System.assertEquals('PAYMENT_REMITTANCE', ledgerEntry.Entry_Type__c, 'The ledger should record the remittance payment.');
            System.assertEquals(-150.00, ledgerEntry.Amount__c, 'The remittance ledger entry should be negative.');
        }
    }

    private static User createSystemAdminUser() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User adminUser = new User(
            Alias = 'admin',
            Email = 'admin' + DateTime.now().getTime() + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'admin' + DateTime.now().getTime() + '@example.com'
        );
        insert adminUser;

        PermissionSet billingAccess = new PermissionSet(
            Name = 'TestBillingAccess' + String.valueOf(DateTime.now().getTime()),
            Label = 'Test Billing Access'
        );
        insert billingAccess;

        List<ObjectPermissions> objectPermissions = new List<ObjectPermissions>{
            new ObjectPermissions(
                ParentId = billingAccess.Id,
                SObjectType = 'Account',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true
            ),
            new ObjectPermissions(
                ParentId = billingAccess.Id,
                SObjectType = 'Invoice__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true
            ),
            new ObjectPermissions(
                ParentId = billingAccess.Id,
                SObjectType = 'Payment_Transaction__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true
            ),
            new ObjectPermissions(
                ParentId = billingAccess.Id,
                SObjectType = 'Billing_Ledger_Entry__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true
            ),
            new ObjectPermissions(
                ParentId = billingAccess.Id,
                SObjectType = 'Usage_Record__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true
            )
        };
        insert objectPermissions;

        List<FieldPermissions> fieldPermissions = new List<FieldPermissions>{
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Account__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Status__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Subtotal__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Total_Due__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Tax_Amount__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Stripe_Session_Id__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Stripe_Payment_Link__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Invoice__c', Field = 'Invoice__c.Loyalty_Discount__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Payment_Transaction__c', Field = 'Payment_Transaction__c.Invoice__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Payment_Transaction__c', Field = 'Payment_Transaction__c.Status__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Payment_Transaction__c', Field = 'Payment_Transaction__c.Amount_Received__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Payment_Transaction__c', Field = 'Payment_Transaction__c.Stripe_Payment_Intent_Id__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Billing_Ledger_Entry__c', Field = 'Billing_Ledger_Entry__c.Account__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Billing_Ledger_Entry__c', Field = 'Billing_Ledger_Entry__c.Amount__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Billing_Ledger_Entry__c', Field = 'Billing_Ledger_Entry__c.Entry_Type__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Billing_Ledger_Entry__c', Field = 'Billing_Ledger_Entry__c.Reference_Id__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Billing_Ledger_Entry__c', Field = 'Billing_Ledger_Entry__c.Loyalty_Points_Delta__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Billing_Ledger_Entry__c', Field = 'Billing_Ledger_Entry__c.Transaction_Timestamp__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Usage_Record__c', Field = 'Usage_Record__c.Account__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Usage_Record__c', Field = 'Usage_Record__c.Meter_Type__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Usage_Record__c', Field = 'Usage_Record__c.Quantity__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Usage_Record__c', Field = 'Usage_Record__c.Status__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = billingAccess.Id, SObjectType = 'Usage_Record__c', Field = 'Usage_Record__c.Idempotency_Hash__c', PermissionsRead = true, PermissionsEdit = true)
        };
        insert fieldPermissions;

        insert new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = billingAccess.Id
        );

        return adminUser;
    }

    private class StripePaymentLinkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id":"cs_test_123","url":"https://checkout.stripe.com/pay/cs_test_123"}');
            return res;
        }
    }
}
