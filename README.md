# APSS Shopify Enhancements

Per-tenant extension (PTE) for Microsoft Dynamics 365 Business Central (BC 28) integrating with the Microsoft Shopify Connector. This extension delivers enhanced product image filtering, `APSS Approved` item approval gates, automated 6-metafield synchronization (including `custom.price_valid_until`), persistent DB staging for price ending dates, admin diagnostic logging, and dynamic Shopify readiness validation.

---

## 1. Project Overview

- **App Name:** APSS Shopify Enhancements
- **App Publisher:** APSS
- **Target Platform:** Microsoft Dynamics 365 Business Central (BC 28)
- **Integration Layer:** Standard Microsoft Shopify Connector (`Microsoft.Integration.Shopify`)
- **ID Range:** `90300` to `90349`
- **Build Status:** Clean build (`0 Errors, 0 Warnings`) using AL Compiler `v17`

The primary purpose of this extension is to extend standard Business Central and Microsoft Shopify Connector capabilities, ensuring that only approved items with valid pictures and required metadata are published to Shopify, while automatically synchronizing unit pricing, price valid until dates, and custom product metafields.

---

## 2. Implemented Features Summary

### Phase 1: Publishing Controls & Product Metafields
- **APSS Approved Gate:** Items where `APSS Approved = false` (Field 50001, Boolean) are strictly excluded from both Add Items (new product creation) and Sync Products (existing product updates).
- **Image Gate:** Items must have at least one image (`Picture.Count() > 0`). Missing images filter items out silently without creating error log noise.
- **Shopify Readiness Validation:** Dynamic calculation on Item records (`APSS Has Shopify Image`, `APSS Shopify Ready`, `APSS Shopify Validation`) evaluating `APSS Approved`, `Picture`, `Customer Item Reference No.`, `Brand`, and `Base Unit of Measure`. Includes UI refresh actions on the Item List page.
- **Product Title Formatting:** Formatted as `[Brand] - [Vendor Item No.] - [Description]` using dynamic `RecordRef`/`FieldRef` field lookup for `APSS Brand`.
- **Custom Metafield Sync:** Automatically synchronizes 5 core product metafields to Shopify Admin:
  1. `custom.brand`: Dynamic lookup for `APSS Brand` field data from Item.
  2. `custom.manufacture_number`: Mapped from `Item Reference."Reference No."` where `Reference Type = Customer`.
  3. `custom.uom`: Strictly mapped from `Item."Base Unit of Measure"`.
  4. `custom.incoterms`: Fixed default text value `'EXW'`.
  5. `custom.lead_time`: Calculated from `Item."Lead Time Calculation"` as integer number of days.

### Phase 2: Pricing Integration, Price Valid Until & Staging Infrastructure
- **Unit Price Calculation Override (Quantity = 1.0):** Overrides standard Shopify Connector price calculation by forcing `Quantity = 1.0` on a temporary quote calculation. Evaluates minimum quantity thresholds on Sales Price lines to capture the exact unit price (`$123.45` LCY -> converted to `$158.902` SGD via BC Shop currency exchange rate `1.287177`).
- **Dual Pricing Engine Support:** Captures ending dates and best unit prices from both BC pricing engines:
  - **Legacy Pricing:** `Codeunit 7000 "Sales Price Calc. Mgt."` (event `OnAfterCalcBestUnitPrice`).
  - **New Pricing:** `Codeunit 7020 "Sales Line - Price"` (event `OnAfterSetPrice`).
- **Persistent Staging Architecture (`Table 90306 APSS Item Price Ending Date`):** Resolves NST background session boundary risks (where in-memory dictionaries fail across async job queues). Stores `Item No.`, `Shop Code`, `Ending Date`, `Has Variant Conflict`, `Last Updated`, and `Last Session ID`. Automatically purges stale staging data per `Shop Code` at the start of each sync pass.
- **Product Price Ending Date Metafield (`custom.price_valid_until`):** Synchronizes captured ending dates to Shopify Metafield in ISO `date` format (`YYYY-MM-DD`, e.g., `2026-09-30`). Omitted when variant ending date conflicts occur (`Has Variant Conflict = true`).
- **Admin Diagnostic Logging (`Table 90305` & `Page 90305 APSS Diagnostic Logs`):** Retains operational diagnostic logs (`Session ID`, `Context`, `Item No.`, `Shop Code`, `Calculated Price`, `Captured Ending Date`, `Error Text`, `Details`) with an Admin UI page for long-term production maintenance.

---

## 3. High-Level System Architecture

```
Business Central Item
        │
        ├─► Add Items (Report 30106) ─────────► APSS Approved & Image Gate ──► Shopify Product Creation
        │
        ├─► Existing Product Sync (Codeunit 30178) ─► APSS Approved & Image Gate ──► Shopify Product Update
        │
        ├─► Pricing Engine Override ──────────► Temp Quote (Qty = 1.0) ─────► Captured Unit Price ($158.902 SGD)
        │                                             │
        │                                             ├─► Legacy Pricing (CU 7000) ──┐
        │                                             └─► New Pricing (CU 7020) ────┴─► APSS Item Price Ending Date (Table 90306)
        │
        ├─► Readiness Management (Codeunit 90301) ──► Item List Page UI Updates
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
│   ├── APSSItemPriceEndingDate.Table.al    # Persistent staging table for captured ending dates (Table 90306)
│   ├── ItemListShopify.PageExt.al          # Readiness fields and refresh actions on Item List (PageExt 90300)
│   ├── ItemShopifyReady.TableExt.al        # Custom readiness fields on Item table (TableExt 90300)
│   ├── ShopifyEnhancements.PermissionSet.al # Extension permissions (PermissionSet 90300)
│   ├── ShopifyProductTitle.Codeunit.al      # Product title formatting & Customer Reference lookup (Codeunit 90300)
│   ├── ShopifyReadinessMgt.Codeunit.al      # Readiness validation logic (Codeunit 90301)
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
alc.exe /project:"." /packagecachepath:".alpackages" /out:"APSS_APSS Shopify Enhancements_1.0.0.0.app"
```

### Deployment Configuration (`launch.json`)
```json
{
  "environmentType": "Sandbox",
  "environmentName": "June9",
  "authenticator": "UserPassword",
  "schemaUpdateMode": "Synchronize"
}
```

---

## 6. Detailed Phase Documentation

For full architectural breakdown, execution trace logs, historical and current E2E evidence summaries, refer to the documentation files:

- 📖 [**Phase 1 Technical & Verification Document**](docs/PHASE_1.md)
- 📖 [**Phase 2 Technical & Verification Document**](docs/PHASE_2.md)

---

## 7. Project Status

| Milestone | Status |
| :--- | :--- |
| **Phase 1 Implementation & Verification** | **PASS** |
| **Phase 2 Pricing & Staging Implementation** | **PASS** |
| **Phase 2 Metafield (`price_valid_until`)** | **PASS** |
| **AL Code Compilation (`alc.exe`)** | **PASS** (`0` errors, `0` warnings) |
| **Shopify E2E Storefront & Admin Validation** | **PASS** |
| **Production Deployment Status** | **READY FOR DEPLOYMENT** |
