import { LightningElement } from 'lwc';
import getAccountsBatch from '@salesforce/apex/AccountController.getAccountsBatch';

export default class Homepage extends LightningElement {
    searchTerm = '';
    accounts = [];
    error;
    loading = false;
    allLoaded = false;
    batchSize = 170;
    offset = 0;

    connectedCallback() {
        this.loadAccountsBatch();
    }

    loadAccountsBatch() {
        if (this.loading || this.allLoaded) {
            return;
        }

        this.loading = true;
        getAccountsBatch({
            limitSize: this.batchSize,
            offset: this.offset
        }).then((result) => {
                if (result && result.length) {
                    this.accounts = [...this.accounts, ...result];
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
        this.loadAccountsBatch();
    }

    get loadMoreLabel() {
        return this.loading ? 'Loading...' : 'Load More';
    }

    get noAccounts() {
        return !this.loading && (!this.accounts || this.accounts.length === 0);
    }
}
