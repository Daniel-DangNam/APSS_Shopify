# APSS Shopify Enhancements

Per-tenant extension (PTE) for Microsoft Dynamics 365 Business Central (BC 28) integrating with the Microsoft Shopify Connector. This extension delivers enhanced product image filtering, `APSS Approved` item approval gates, automated 6-metafield synchronization (including `custom.price_valid_until`), persistent DB staging for price ending dates, admin diagnostic logging, dynamic Shopify readiness validation, 4-branch SKU Precheck flow with automatic Client Credentials OAuth token refresh, interactive Shopify Reconcile Log UI with bulk management, and automated HTML email notifications to Procurement.

---

## 1. Project Overview

- **App Name:** APSS Shopify Enhancements
- **App Publisher:** APSS
- **Target Platform:** Microsoft Dynamics 365 Business Central (BC 28)
- **Integration Layer:** Standard Microsoft Shopify Connector (`Microsoft.Integration.Shopify`)
- **ID Range:** `90300` to `90349`
- **Build Status:** Clean build (`0 Errors, 0 Warnings`) using AL Compiler `v17`

The primary purpose of this extension is to extend standard Business Central and Microsoft Shopify Connector capabilities, ensuring that only approved items with valid pictures and required metadata are published to Shopify, while automatically synchronizing unit pricing, price valid until dates, custom product metafields, enforcing 4-branch SKU Precheck protection, and dispatching rich HTML email notifications to Procurement.

---

## 2. Implemented Features Summary

### Phase 1: Publishing Controls & Product Metafields

- **APSS Approved Gate:** Items where `APSS Approved = false` (Field 50001, Boolean) are strictly excluded from both Add Items (new product creation) and Sync Products (existing product updates).
- **Image Gate:** Items must have at least one image (`Picture.Count() > 0`). Missing images filter items out silently without creating error log noise.
- **Shopify Readiness Validation:** Evaluates hard readiness: `APSS Approved`, `Picture`, `Brand`, `Description`, and `Base Unit of Measure`. Customer Item Reference is strictly excluded from hard readiness.
- **Product Title Formatting:** Deterministic fallback format `Brand + Description` with anti-duplication (e.g. if Description already starts with Brand, Brand is not prepended twice). Excludes Vendor Item No. and Customer Reference.
- **Custom Metafield Sync:** Automatically synchronizes core product and variant metafields to Shopify Admin:
  1. `custom.brand`: Dynamic lookup for exact `APSS Brand` field data from Item.
  2. `custom.manufacture_number`: Mapped from `Item.Description` (matching Kathy's instructions & June's production example).
  3. `custom.uom`: Strictly mapped from `Item."Base Unit of Measure"`.
  4. `custom.incoterms`: Fixed default text value `'EXW'`.
  5. `custom.lead_time`: Calculated from `Item."Lead Time Calculation"` as integer number of days (omitted if empty).
  6. `custom.price_valid_until`: Date format `YYYY-MM-DD` (30 days validity for synced items if no price list ending date).
  7. `custom.manufacture_number` (Variant Metafield): Google MPN fallback populated from `Item.Description`.
- **Native SEO:** Automatically populates `ShopifyProduct."SEO Title"` (<= 70 chars) and `ShopifyProduct."SEO Description"` (plain text Marketing Text, <= 160 chars).

### Phase 2: Pricing Integration, Price Valid Until & Staging Infrastructure

- **Unit Price Calculation Override (Quantity = 1.0):** Overrides standard Shopify Connector price calculation by forcing `Quantity = 1.0` on a temporary quote calculation. Evaluates minimum quantity thresholds on Sales Price lines and returns the true converted SGD price without overwriting by raw LCY price.
- **Dual Pricing Engine Support:** Captures ending dates and best unit prices from both BC pricing engines:
  - **Legacy Pricing:** `Codeunit 7000 "Sales Price Calc. Mgt."` (event `OnAfterCalcBestUnitPrice`).
  - **New Pricing:** `Codeunit 7020 "Sales Line - Price"` (event `OnAfterSetPrice`).
- **Persistent Staging Architecture (`Table 90306 APSS Item Price Ending Date`):** Resolves NST background session boundary risks (where in-memory dictionaries fail across async job queues). Stores `Item No.`, `Shop Code`, `Ending Date`, `Has Variant Conflict`, `Last Updated`, and `Last Session ID`. Automatically purges stale staging data per `Shop Code` at the start of each sync pass.
- **Interactive Item Selection Modal & Targeted Dual Sync:** Dedicated UI Action button on the Item List page (`Add Ready Items to Shopify`) that opens a selection modal page (`Page 90300 APSS Shopify Item Selection`) with visual Checkbox controls (`[ ]` / `[✓]`) and `Select All` / `Deselect All` actions. Segregates `New Ready` items (runs `Report 30106` with `SyncInventory = true`) and `Modified Ready` items (runs `Report 30108` with targeted `SystemId` filter < 1s). Eliminates manual timestamp hack.
- **Automated HTML Email Notification System:**
  - Configurable `Procurement Email` field added to `Shpfy Shop Card` (no hardcoded emails).
  - Dedicated `Email Scenario` extension (`APSS Shopify Procurement` enum value 90300) mapped to `IT.Support@apss.com` sender account in BC.
  - **Success Notifications:** Dispatches executive summary HTML email with green header (`#008060`), statistics cards (`New Created`, `Modified Updated`), and detailed item table with green/amber status badges.
  - **Error Notifications:** Catches sync failures for both New and Modified items, sending a red HTML alert email (`#dc2626`) detailing error title, technical error traceback, and affected products table.
- **Admin Diagnostic Logging (`Table 90305` & `Page 90305 APSS Diagnostic Logs`):** Retains operational diagnostic logs recording currency conversion, source prices, exchange rates, and errors for production troubleshooting.

### Phase 3: 4-Branch SKU Precheck, OAuth Token Management & Reconcile Log UI

- **4-Branch SKU Precheck Logic (`Codeunit 90304 APSS Shopify SKU Precheck`):**
  - **Create:** SKU does not exist on Shopify $\rightarrow$ Item proceeds to product creation.
  - **Update:** SKU exists on Shopify and is mapped correctly to the current BC item $\rightarrow$ Item proceeds to update.
  - **Block (Needs Reconciliation):** SKU exists on Shopify but is unmapped or mapped to a different BC item. Sync is blocked and logged in `Shopify Reconcile Log`.
  - **Block (Stale Mapping):** Mapping exists in BC but SKU/Product was deleted directly on Shopify Admin. Sync is blocked and logged in `Shopify Reconcile Log`.
- **Dynamic OAuth Client Credentials Auto-Refresh:**
  - Client ID and Client Secret are stored dynamically in `IsolatedStorage` via `Shpfy Shop Card` masked fields (**zero hardcoded credentials in codebase or git**).
  - Automatically fetches and refreshes 24-hour access tokens via `POST https://{shop}.myshopify.com/admin/oauth/access_token` using `grant_type=client_credentials`.
- **Shopify Reconcile Log UI & Bulk Action Management (`Page 90304` & `Table 90304`):**
  - Editable table view with interactive visual checkbox column (`Selected`).
  - **Bulk Action Actions:**
    - `Select All` / `Deselect All`: Quick selection of log rows.
    - `Mark as Resolved`: Resets selected items back to `New Ready` or `Modified Ready` for re-synchronization.
    - `Mark ALL as Resolved`: Mass resets all logged items back to ready status.
    - `Delete Selected`: Bulk purges chosen log entries to prevent log duplication during repeated sync passes.
- **Ghost Record Auto-Purge:** Automatically identifies and removes incomplete mapping records (`Id = 0`) prior to precheck evaluation.

---

## 3. High-Level System Architecture

```
Business Central Item
        │
        ├─► Add Ready Items Modal (Page 90300) ──► Visual Checkbox & Selection ──► Targeted Export (< 1s)
        │                                                                               │
        │                                                                               ├─► SKU Precheck (CU 90304)
        │                                                                               │     ├─► Create (Pass) ──────────► Report 30106 Creation
        │                                                                               │     ├─► Update (Pass) ──────────► Report 30108 Sync
        │                                                                               │     └─► Block ──────────► Reconcile Log (Table 90304)
        │                                                                               │
        │                                                                               └─► HTML Email Dispatch (Codeunit 90303)
        │                                                                                     ├─► Success: Green HTML Table & Stats
        │                                                                                     └─► Error: Red HTML Alert & Error Details
        │
        ├─► Pricing Engine Override ──────────► Temp Quote (Qty = 1.0) ─────► Captured Unit Price ($158.902 SGD)
        │                                             │
        │                                             ├─► Legacy Pricing (CU 7000) ──┐
        │                                             └─► New Pricing (CU 7020) ────┴─► APSS Item Price Ending Date (Table 90306)
        │
        ├─► Readiness Management (Codeunit 90301) ──► Item List Page UI Updates & Auto Status Transition
        │
        └─► Product Metafield Sync (Codeunit 90302) ─► GraphQL metafieldsSet ──────► Shopify Admin Product Metafields
                                                            ├─► custom.brand
                                                            ├─► custom.manufacture_number
                                                            ├─► custom.uom
                                                            ├─► custom.incoterms
                                                            ├─► custom.lead_time
                                                            └─► custom.price_valid_until (Date: YYYY-MM-DD)
```

---

## 4. Repository Structure

```
APSS_Shopify/
├── .alpackages/                            # Symbol packages for dependencies
├── .vscode/                                # VS Code configuration (launch.json)
├── docs/
│   ├── PHASE_1.md                          # Detailed Phase 1 technical & verification document
│   └── PHASE_2.md                          # Detailed Phase 2 technical & verification document
├── src/
│   ├── AddItemImageGate.ReportExt.al       # Image & Approval Gate for Add Items report (ReportExt 90300)
│   ├── APSSDiagnosticLog.Table.al          # Operational diagnostic logging table (Table 90305)
│   ├── APSSDiagnosticLogs.Page.al          # Admin diagnostic logs UI page (Page 90305)
│   ├── APSSEmailScenario.EnumExt.al        # Email Scenario extension for Procurement (EnumExt 90300)
│   ├── APSSItemPriceEndingDate.Table.al    # Persistent staging table for captured ending dates (Table 90306)
│   ├── APSSShopifyEmailMgt.Codeunit.al      # Rich HTML email generator & dispatcher (Codeunit 90303)
│   ├── APSSShopifySKUPrecheck.Codeunit.al   # 4-branch SKU Precheck & OAuth client credentials manager (Codeunit 90304)
│   ├── APSSShpfyItemSelBuffer.Table.al     # Temporary buffer table for selection page with checkbox (Table 90300)
│   ├── APSSShpfyReconcileLog.Page.al       # Reconcile Log UI page with bulk actions (Page 90304)
│   ├── APSSShpfyReconcileLog.Table.al      # Reconcile Log table for sync blockers (Table 90304)
│   ├── APSSShpfyShop.TableExt.al           # Procurement Email & Precheck setup fields on Shpfy Shop (TableExt 90301)
│   ├── APSSShpfyShopCard.PageExt.al        # Procurement Email & OAuth credentials UI on Shop Card (PageExt 90301)
│   ├── ItemListShopify.PageExt.al          # Readiness fields, status styles, Add Ready Items action & Email trigger (PageExt 90300)
│   ├── ItemShopifyReady.TableExt.al        # Custom readiness fields on Item table (TableExt 90300)
│   ├── ShopifyEnhancements.PermissionSet.al # Extension permissions (PermissionSet 90300)
│   ├── ShopifyItemSelection.Page.al        # Selection modal page with visual checkbox (Page 90300)
│   ├── ShopifyItemSyncStatus.Enum.al       # Sync status enum definition (Enum 90300)
│   ├── ShopifyProductTitle.Codeunit.al      # Product title formatting & Customer Reference lookup (Codeunit 90300)
│   ├── ShopifyReadinessMgt.Codeunit.al      # Readiness & sync status evaluation (Codeunit 90301)
│   └── ShopifySyncEvents.Codeunit.al        # Pricing override, event subscribers & metafield sync (Codeunit 90302)
├── app.json                                # AL Extension manifest
└── README.md                               # Main GitHub repository README
```

---

## 5. Build & Deployment Instructions

### Prerequisites

- Microsoft Dynamics 365 Business Central (BC 28 or compatible sandbox environment)
- Standard Microsoft Shopify Connector (`Microsoft.Integration.Shopify`)
- AL Language Extension for Visual Studio Code (`v17`)
- Downloaded package dependencies in `.alpackages/` (`System`, `Base Application`, `Microsoft Shopify Connector`)

### Build Command

Compile the extension package using Microsoft AL Compiler (`alc.exe`):

```cmd
alc.exe /project:"." /packagecachepath:".alpackages" /out:"APSS_APSS Shopify Enhancements_1.0.0.14.app"
```

### Deployment Configuration (`launch.json`)

```json
{
  "environmentType": "Sandbox",
  "environmentName": "June9",
  "authenticator": "UserPassword",
  "schemaUpdateMode": "ForceSync"
}
```

---

## 6. Detailed Phase Documentation

For full architectural breakdown, execution trace logs, historical and current E2E evidence summaries, refer to the documentation files:

- 📖 [**Phase 1 Technical & Verification Document**](docs/PHASE_1.md)
- 📖 [**Phase 2 Technical & Verification Document**](docs/PHASE_2.md)

---

## 7. Project Status

| Milestone                                    | Status                                                                                                           |
| :------------------------------------------- | :--------------------------------------------------------------------------------------------------------------- |
| **Phase 1 Implementation & Verification**    | **PASS**                                                                                                         |
| **Phase 2 Pricing & Staging Implementation** | **PASS**                                                                                                         |
| **Phase 2 Metafield (`price_valid_until`)**  | **PASS**                                                                                                         |
| **Phase 3 SKU Precheck (4-Branch Flow)**     | **PASS** (Create, Update, Block Needs Reconciliation, Block Stale Mapping verified)                              |
| **Phase 3 Dynamic OAuth Token Refresh**      | **PASS** (Client Credentials flow, 24h token auto-refresh, IsolatedStorage security verified)                    |
| **Phase 3 Reconcile Log UI & Bulk Actions**  | **PASS** (Checkboxes, Select All, Deselect All, Mark as Resolved, Delete Selected verified)                      |
| **Automated HTML Email Notification System** | **PASS** (Configurable setup, zero hardcoding, Success & Error HTML templates verified)                          |
| **AL Code Compilation (`alc.exe`)**          | **PASS** (`0` errors, `0` warnings, version `1.0.0.14`)                                                          |
| **Kathy/June Requirement Refactor**          | **Code Implemented** (Field mapping, Title anti-duplication, SEO, Inventory sync, Report 30106/30108 separation) |
| **Production Deployment Status**             | **Implementation in progress / Sandbox verification required / Not production-ready**                            |
