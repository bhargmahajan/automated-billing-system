import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboard from '@salesforce/apex/BillingDashboardController.getDashboard';
import generatePaymentLink from '@salesforce/apex/BillingDashboardController.generatePaymentLink';

const COLUMNS = [
    {
        label: 'Invoice',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'invoiceNumber' }, target: '_self' }
    },
    { label: 'Account', fieldName: 'accountName', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    {
        label: 'Total due',
        fieldName: 'totalDue',
        type: 'currency',
        typeAttributes: { currencyCode: 'USD' }
    },
    { label: 'Created', fieldName: 'createdDate', type: 'date' },
    { label: 'Link status', fieldName: 'paymentLinkStatus', type: 'text' },
    {
        label: 'Payment link',
        fieldName: 'paymentLink',
        type: 'url',
        typeAttributes: { label: 'Open link', target: '_blank' }
    },
    {
        type: 'button',
        fixedWidth: 180,
        typeAttributes: {
            label: { fieldName: 'actionLabel' },
            name: 'generate_payment_link',
            title: { fieldName: 'actionTitle' },
            variant: { fieldName: 'actionVariant' },
            disabled: { fieldName: 'actionDisabled' }
        }
    }
];

export default class BillingDashboard extends LightningElement {
    columns = COLUMNS;
    dashboard;
    wiredDashboardResult;
    errorMessage;
    isLoading = true;
    isGenerating = false;
    pollTimer;

    @wire(getDashboard)
    wiredDashboard(result) {
        this.wiredDashboardResult = result;
        if (result.data) {
            this.dashboard = result.data;
            this.errorMessage = undefined;
            this.isLoading = false;
            this.updatePolling();
        } else if (result.error) {
            this.dashboard = undefined;
            this.errorMessage = this.getErrorMessage(result.error);
            this.isLoading = false;
            this.stopPolling();
        }
    }

    get hasDashboard() {
        return Boolean(this.dashboard);
    }

    get invoiceCount() {
        return this.dashboard?.invoiceCount ?? 0;
    }

    get paidInvoiceCount() {
        return this.dashboard?.paidInvoiceCount ?? 0;
    }

    get outstandingBalance() {
        return this.dashboard?.outstandingBalance ?? 0;
    }

    get paymentsReceived() {
        return this.dashboard?.paymentsReceived ?? 0;
    }

    get pendingUsageCount() {
        return this.dashboard?.pendingUsageCount ?? 0;
    }

    get pendingUsageQuantity() {
        return this.dashboard?.pendingUsageQuantity ?? 0;
    }

    get invoiceRows() {
        return (this.dashboard?.invoices ?? []).map((invoice) => {
            const generating = invoice.paymentLinkStatus === 'GENERATING';
            const failed = invoice.paymentLinkStatus === 'FAILED';
            return {
                ...invoice,
                recordUrl: `/lightning/r/Invoice__c/${invoice.id}/view`,
                paymentLink: invoice.paymentLink || undefined,
                actionLabel: generating ? 'Generating...' : failed ? 'Retry link' : 'Generate link',
                actionTitle: failed ? 'Retry payment link generation' : 'Generate Stripe payment link',
                actionVariant: failed ? 'neutral' : 'brand',
                actionDisabled: !invoice.canGeneratePaymentLink || generating || this.isGenerating
            };
        });
    }

    get hasMoreInvoices() {
        return this.dashboard?.invoiceCount > this.invoiceRows.length;
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredDashboardResult);
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
            this.isLoading = false;
        }
    }

    async handleRowAction(event) {
        if (event.detail.action.name !== 'generate_payment_link') {
            return;
        }

        this.isGenerating = true;
        try {
            await generatePaymentLink({ invoiceId: event.detail.row.id });
            this.showToast('Payment link requested', 'The invoice is locked while the link is generated.', 'success');
            await refreshApex(this.wiredDashboardResult);
        } catch (error) {
            this.showToast('Could not generate payment link', this.getErrorMessage(error), 'error');
        } finally {
            this.isGenerating = false;
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    updatePolling() {
        const hasGeneratingInvoice = this.dashboard?.invoices?.some(
            (invoice) => invoice.paymentLinkStatus === 'GENERATING'
        );
        if (hasGeneratingInvoice && !this.pollTimer) {
            this.pollTimer = window.setInterval(() => {
                if (this.isConnected) {
                    refreshApex(this.wiredDashboardResult);
                }
            }, 3000);
        } else if (!hasGeneratingInvoice) {
            this.stopPolling();
        }
    }

    stopPolling() {
        if (this.pollTimer) {
            window.clearInterval(this.pollTimer);
            this.pollTimer = undefined;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
