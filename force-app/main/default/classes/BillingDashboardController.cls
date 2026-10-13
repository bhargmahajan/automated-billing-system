public with sharing class BillingDashboardController {
    public class InvoiceRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String invoiceNumber { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal totalDue { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String paymentLink { get; set; }
        @AuraEnabled public String paymentLinkStatus { get; set; }
        @AuraEnabled public Boolean canGeneratePaymentLink { get; set; }
    }

    public class DashboardData {
        @AuraEnabled public Integer invoiceCount { get; set; }
        @AuraEnabled public Integer paidInvoiceCount { get; set; }
        @AuraEnabled public Decimal outstandingBalance { get; set; }
        @AuraEnabled public Decimal paymentsReceived { get; set; }
        @AuraEnabled public Integer pendingUsageCount { get; set; }
        @AuraEnabled public Decimal pendingUsageQuantity { get; set; }
        @AuraEnabled public List<InvoiceRow> invoices { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboard() {
        DashboardData dashboard = new DashboardData();
        dashboard.invoiceCount = 0;
        dashboard.paidInvoiceCount = 0;
        dashboard.outstandingBalance = 0;
        dashboard.paymentsReceived = 0;
        dashboard.pendingUsageCount = 0;
        dashboard.pendingUsageQuantity = 0;
        dashboard.invoices = new List<InvoiceRow>();

        for (AggregateResult invoiceStats : [
            SELECT Status__c invoiceStatus, COUNT(Id) invoiceCount
            FROM Invoice__c
            WITH USER_MODE
            GROUP BY Status__c
        ]) {
            Integer countForStatus = (Integer) invoiceStats.get('invoiceCount');
            dashboard.invoiceCount += countForStatus;
            if ((String) invoiceStats.get('invoiceStatus') == 'PAID') {
                dashboard.paidInvoiceCount = countForStatus;
            }
        }

        List<AggregateResult> outstandingStats = [
            SELECT SUM(Total_Due__c) totalDue
            FROM Invoice__c
            WHERE Status__c IN ('POSTED', 'OVERDUE')
            WITH USER_MODE
        ];
        if (!outstandingStats.isEmpty() && outstandingStats[0].get('totalDue') != null) {
            dashboard.outstandingBalance = (Decimal) outstandingStats[0].get('totalDue');
        }

        List<AggregateResult> paymentStats = [
            SELECT SUM(Amount_Received__c) totalReceived
            FROM Payment_Transaction__c
            WHERE Status__c = 'SUCCEEDED'
            WITH USER_MODE
        ];
        if (!paymentStats.isEmpty() && paymentStats[0].get('totalReceived') != null) {
            dashboard.paymentsReceived = (Decimal) paymentStats[0].get('totalReceived');
        }

        List<AggregateResult> usageStats = [
            SELECT COUNT(Id) pendingCount, SUM(Quantity__c) pendingQuantity
            FROM Usage_Record__c
            WHERE Status__c = 'PENDING'
            WITH USER_MODE
        ];
        if (!usageStats.isEmpty()) {
            dashboard.pendingUsageCount = (Integer) usageStats[0].get('pendingCount');
            if (usageStats[0].get('pendingQuantity') != null) {
                dashboard.pendingUsageQuantity = (Decimal) usageStats[0].get('pendingQuantity');
            }
        }

        for (Invoice__c invoice : [
            SELECT Id, Name, Account__r.Name, Status__c, Total_Due__c,
                CreatedDate, Stripe_Payment_Link__c, Payment_Link_Status__c
            FROM Invoice__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            InvoiceRow row = new InvoiceRow();
            row.id = invoice.Id;
            row.invoiceNumber = invoice.Name;
            row.accountName = invoice.Account__r.Name;
            row.status = invoice.Status__c;
            row.totalDue = invoice.Total_Due__c;
            row.createdDate = invoice.CreatedDate;
            row.paymentLink = invoice.Stripe_Payment_Link__c;
            row.paymentLinkStatus = String.isBlank(invoice.Payment_Link_Status__c)
                ? 'NOT_REQUESTED'
                : invoice.Payment_Link_Status__c;
            row.canGeneratePaymentLink =
                String.isBlank(invoice.Stripe_Payment_Link__c) &&
                row.paymentLinkStatus != 'GENERATING' &&
                (invoice.Status__c == 'POSTED' || invoice.Status__c == 'OVERDUE') &&
                invoice.Total_Due__c > 0;
            dashboard.invoices.add(row);
        }

        return dashboard;
    }

    @AuraEnabled
    public static void generatePaymentLink(Id invoiceId) {
        if (invoiceId == null) {
            throw new AuraHandledException('Select an invoice before generating a payment link.');
        }

        List<Invoice__c> matchingInvoices = [
            SELECT Id, Status__c, Total_Due__c, Stripe_Payment_Link__c,
                Payment_Link_Status__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            WITH USER_MODE
            FOR UPDATE
        ];
        if (matchingInvoices.isEmpty()) {
            throw new AuraHandledException('The invoice is unavailable or you do not have access to it.');
        }

        Invoice__c invoice = matchingInvoices[0];
        if (String.isNotBlank(invoice.Stripe_Payment_Link__c)) {
            throw new AuraHandledException('This invoice already has a payment link.');
        }
        if (invoice.Payment_Link_Status__c == 'GENERATING') {
            throw new AuraHandledException('A payment link is already being generated for this invoice.');
        }
        if (invoice.Status__c != 'POSTED' && invoice.Status__c != 'OVERDUE') {
            throw new AuraHandledException('Only posted or overdue invoices can have a payment link.');
        }
        if (invoice.Total_Due__c == null || invoice.Total_Due__c <= 0) {
            throw new AuraHandledException('The invoice must have a positive balance to generate a payment link.');
        }

        invoice.Payment_Link_Status__c = 'GENERATING';
        update as user invoice;
        System.enqueueJob(new StripePaymentLinkDispatcher(new List<Id>{ invoice.Id }));
    }
}
