import { LightningElement } from 'lwc';
import getAccountsBatch from '@salesforce/apex/AccountController.getAccountsBatch';
import getLoyaltySummary from '@salesforce/apex/AccountController.getLoyaltySummary';
import getLoyaltyTransactions from '@salesforce/apex/AccountController.getLoyaltyTransactions';

export default class Homepage extends LightningElement {
    searchTerm = '';
    accounts = [];
    selectedAccount = null;
    error;
    loading = false;
    allLoaded = false;
    batchSize = 170;
    offset = 0;
    activeSections = ['accountDetails', 'loyalty'];

    // Loyalty transactions state
    loyaltySummary = { totalEarned: 0, totalRedeemed: 0, available: 0 };
    transactions = [];
    txLoading = false;
    txAllLoaded = false;
    txOffset = 0;
    txBatchSize = 170;

    connectedCallback() {
        this.loadAccounts();
    }

    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value.trim();
        this.resetPagination();
        this.selectedAccount = null;
        this.clearLoyaltyState();
        this.loadAccounts();
    }

    resetPagination() {
        this.accounts = [];
        this.offset = 0;
        this.allLoaded = false;
        this.error = undefined;
    }

    loadAccounts() {
        if (this.loading || this.allLoaded) {
            return;
        }

        this.loading = true;
        getAccountsBatch({
            searchTerm: this.searchTerm,
            limitSize: this.batchSize,
            offset: this.offset
        }).then((result) => {
                if (result && result.length) {
                    // attach cssClass for template binding
                    const mapped = result.map(acc => ({ ...acc, cssClass: this.getAccountClass(acc.Id) }));
                    this.accounts = [...this.accounts, ...mapped];
                    this.offset += this.batchSize;

                    if (result.length < this.batchSize) {
                        this.allLoaded = true;
                    }
                } else {
                    this.allLoaded = true;
                }
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error;
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleLoadMore() {
        this.loadAccounts();
    }

    handleSelectAccount(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const sameAccount = this.selectedAccount && this.selectedAccount.Id === accountId;

        if (sameAccount) {
            this.selectedAccount = null;
            this.clearLoyaltyState();
        } else {
            this.selectedAccount = this.accounts.find(acc => acc.Id === accountId);
            this.loadLoyaltySummary();
            this.resetTransactions();
            this.loadTransactions();
        }

        this.updateAccountClasses();
    }

    getAccountClass(accountId) {
        const baseClass = 'slds-box slds-m-bottom_small account-item';
        return this.selectedAccount && this.selectedAccount.Id === accountId
            ? `${baseClass} selected`
            : baseClass;
    }

    updateAccountClasses() {
        this.accounts = this.accounts.map(acc => ({
            ...acc,
            cssClass: this.getAccountClass(acc.Id)
        }));
    }

    // Loyalty summary and transactions
    loadLoyaltySummary() {
        if (!this.selectedAccount) return;

        getLoyaltySummary({ accountId: this.selectedAccount.Id })
            .then(res => {
                this.loyaltySummary = res || { totalEarned: 0, totalRedeemed: 0, available: 0 };
            })
            .catch(err => {
                this.error = err;
            });
    }

    resetTransactions() {
        this.transactions = [];
        this.txOffset = 0;
        this.txAllLoaded = false;
        this.txLoading = false;
    }

    clearLoyaltyState() {
        this.loyaltySummary = { totalEarned: 0, totalRedeemed: 0, available: 0 };
        this.resetTransactions();
    }

    loadTransactions() {
        if (!this.selectedAccount || this.txLoading || this.txAllLoaded) return;

        this.txLoading = true;
        getLoyaltyTransactions({
            accountId: this.selectedAccount.Id,
            limitSize: this.txBatchSize,
            offset: this.txOffset
        }).then(res => {
            if (res && res.length) {
                this.transactions = [...this.transactions, ...res];
                this.txOffset += this.txBatchSize;
                if (res.length < this.txBatchSize) this.txAllLoaded = true;
            } else {
                this.txAllLoaded = true;
            }
        }).catch(err => {
            this.error = err;
        }).finally(() => {
            this.txLoading = false;
        });
    }

    handleLoadMoreTransactions() {
        this.loadTransactions();
    }

    get loadMoreLabel() {
        return this.loading ? 'Loading...' : 'Load More';
    }

    get loadMoreTxLabel() {
        return this.txLoading ? 'Loading...' : 'Load More';
    }

    get noAccounts() {
        return !this.loading && (!this.accounts || this.accounts.length === 0);
    }

    get showAllAccountsLoaded() {
        return this.allLoaded && this.accounts && this.accounts.length > 0;
    }

    get showAllTransactionsLoaded() {
        return this.txAllLoaded && this.transactions && this.transactions.length > 0;
    }
}