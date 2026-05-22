# Automated Billing System

This repository is configured as a Salesforce DX project.

## Project structure

- `sfdx-project.json` — Salesforce DX project descriptor
- `force-app/main/default/` — default metadata source path
- `.gitignore` — ignore Salesforce CLI artifacts and common files

## Setup

### 1. Authorize your Salesforce org

```bash
sf org login web --set-default-org --alias MyOrgAlias
```

For sandbox:

```bash
sf org login web --instance-url https://test.salesforce.com --set-default-org --alias MySandboxAlias
```

### 2. Verify the connection

```bash
sf org list
```

### 3. Open your org

```bash
sf org open
```

### 4. Retrieve or deploy metadata

To deploy local source to the org:

```bash
sf project deploy start --source-dir force-app
```

To retrieve org metadata into the project:

```bash
sf project retrieve start --manifest manifest/package.xml
```

## Using VS Code

Install the official Salesforce Extension Pack and use the Org Browser.
After authorizing your org, reload VS Code and open `Salesforce: Open Org Browser` from the Command Palette.

## Notes

- Keep your source under `force-app/main/default/`
- Use `sf` commands from the repository root
- If you need help pulling specific objects or metadata, I can add example commands
