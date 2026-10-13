# Automated Billing System

A Salesforce DX application for metered SaaS billing. It captures usage, rates it with tiered pricing, creates invoices with tax and loyalty discounts, and integrates with Stripe for checkout and payment confirmation.

## Features

- **Usage ingestion:** `Usage_Event__e` platform events are staged as usage records for rating.
- **Tiered usage pricing:** API calls, storage, and compute hours are priced by `TieredSaaSPricingStrategy`.
- **Automated invoicing:** Batch processing aggregates usage charges, applies eligible loyalty discounts and tax, then creates invoices.
- **Stripe checkout:** Queueable callouts generate an individual Stripe Checkout link for each invoice.
- **Payment confirmation:** A REST webhook verifies Stripe signatures and records successful payments in the invoice, transaction, and billing ledger.
- **Billing dashboard:** Lightning Web Component with invoice, payment, balance, and pending-usage summaries, plus per-invoice payment-link actions.
- **Duplicate-request protection:** Invoice records are locked and marked as generating before a payment-link request is queued. The dashboard reflects generation status and allows retries after a failed request.

## Technology

- Salesforce DX and Apex (project API version 68.0)
- Lightning Web Components
- Salesforce Platform Events, Batch Apex, Queueable Apex, and Custom Metadata
- Stripe Checkout API

## Project layout

```text
force-app/main/default/
  classes/          Apex services, batches, controllers, and tests
  customMetadata/   Tax rate rules
  externalCredentials/
  lwc/              Lightning Web Components
  namedCredentials/ Stripe API endpoint
  objects/          Billing objects, fields, and usage platform event
  permissionsets/   SaaS Billing Ops Admin access
  triggers/         Usage event trigger
```

## Billing flow

1. Publish a `Usage_Event__e` event with an account ID, meter type, quantity, and idempotency hash.
2. The platform-event trigger stages it as a pending `Usage_Record__c`.
3. Run `UsageRatingEngineBatch` to price pending usage and write usage-charge and loyalty-accrual entries to `Billing_Ledger_Entry__c`.
4. The rating batch starts `AutomatedInvoicingBatch`, which creates invoices, applies available points and configured tax rates, and queues Stripe payment-link generation.
5. Stripe sends a signed `checkout.session.completed` event to the webhook endpoint. The handler marks the invoice paid and records the payment transaction and ledger remittance.

The tiered pricing strategy currently supports:

| Meter | Pricing |
| --- | --- |
| `API_CALLS` | First 10,000 are free; next 90,000 at $0.001 each; additional calls at $0.0005 each |
| `STORAGE_GB` | $0.05 per unit |
| `COMPUTE_HOURS` | $0.15 per unit |

Tax rates are supplied as `Tax_Rate_Rule__mdt` custom metadata. The repository includes default US, California, and India rules.

## Prerequisites

- A Salesforce org with access to deploy Apex, custom objects, platform events, named credentials, and Lightning Web Components.
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) installed and available as `sf`.
- A Stripe account and API credentials for the environment you are configuring.

## Set up a Salesforce org

Authorize a production/developer org:

```bash
sf org login web --set-default --alias BillingOrg
```

For a sandbox:

```bash
sf org login web --instance-url https://test.salesforce.com --set-default --alias BillingSandbox
```

Confirm the connection:

```bash
sf org list
```

Deploy the project source:

```bash
sf project deploy start --source-dir force-app --target-org BillingOrg
```

Assign the billing operations permission set to the users who need dashboard and invoice access:

```bash
sf org assign permset --name SaaS_Billing_Ops_Admin --target-org BillingOrg
```

The dashboard is exposed to Lightning **App Pages** and **Home Pages**. After deployment, open Lightning App Builder, add **Billing Dashboard** to the desired page, and activate the page for the appropriate app or users.

## Configure Stripe

The `Stripe_API` named credential points to `https://api.stripe.com` and uses the `Stripe_Auth` external credential. Before enabling payment-link generation:

1. Configure the Stripe API key as the external credential's named-principal secret in Salesforce. Do not store live credentials in source control.
2. Grant the integration users access to the external credential principal. The `SaaS_Billing_Ops_Admin` permission set includes the principal access defined by this project.
3. Configure the Stripe webhook to send `checkout.session.completed` events to:

   ```text
   https://<your-salesforce-domain>/services/apexrest/api/stripe/webhook/v1/
   ```

4. Update the webhook verification code to read the endpoint signing secret from protected configuration before using the endpoint. **The current Apex implementation contains a placeholder webhook secret and is not ready to verify live Stripe signatures.**
5. Review the Checkout success and cancellation URLs in `StripePaymentLinkDispatcher` and replace the example URLs with the URLs for your application.

Use Stripe test credentials and test events in a non-production org before enabling live payments.

## Run tests

Run the focused dashboard and payment-link tests:

```bash
sf apex test run --class-names BillingDashboardControllerTest --target-org BillingOrg --wait 20
```

Run the project billing tests:

```bash
sf apex test run --class-names SaaSBillingProjectTest --target-org BillingOrg --wait 20
```

Tests that execute Stripe callouts use `HttpCalloutMock`; they do not send requests to Stripe.

## Deployment notes

- The project is configured for Salesforce API version 68.0 to support its permission-set metadata.
- Validate the full metadata deployment against the target org. The repository includes legacy Account metadata that may require adjustment if its action overrides are unsupported in that org.
- Do not commit credentials, webhook signing secrets, or other environment-specific values.
- Configure page activation, Stripe credentials, webhook secrets, and redirect URLs separately for each environment.
