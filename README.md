# APSS Shopify Enhancements

Per-tenant extension (PTE) for Microsoft Dynamics 365 Business Central (BC 28) integrating with the Microsoft Shopify Connector to deliver enhanced product image filtering, `APSS Approved` item approval gates, automated 5-metafield synchronization, and dynamic Shopify readiness validation.

---

## 1. Project Overview

- **App Name:** APSS Shopify Enhancements
- **App Publisher:** APSS
- **Target Platform:** Microsoft Dynamics 365 Business Central (BC 28)
- **Integration Layer:** Standard Microsoft Shopify Connector (`Microsoft.Integration.Shopify`)
- **ID Range:** `90300` to `90349`

The primary purpose of this extension is to extend standard Business Central and Microsoft Shopify Connector capabilities, ensuring that only approved items with valid pictures and required metadata are published to Shopify while automatically populating custom product metafields.

---

## 2. Objectives

- Enforce `Item."APSS Approved"` (Field 50001, Boolean) as the sole approval source of truth across both Add Items and Sync Products flows.
- Enforce strict image-presence gates (`Picture.Count() > 0`) before Business Central items can be published as new products or updated as existing products in Shopify.
- Provide dynamic Shopify readiness tracking directly on Business Central Item records.
- Automatically populate and synchronize five core custom product metafields to Shopify Admin.
- Preserve Business Central master data integrity without modifying standard pricing logic or unit of measure setups.

---

## 3. Implemented Features

### Product Publishing Controls
- **APSS Approved Gate:** Items where `APSS Approved = false` are strictly excluded from both Add Items (new product creation) and Sync Products (existing product updates).
- **Image Gate:** Items must have at least one image (`Picture.Count() > 0`). Missing images filter items out silently (Option C) without creating error log noise.
- **Shopify Readiness:** Dynamic calculation on Item records (`APSS Has Shopify Image`, `APSS Shopify Ready`, `APSS Shopify Validation`) evaluating `APSS Approved`, `Picture`, `Customer Item Reference No.`, `Brand`, and `Base Unit of Measure`.

### Shopify Metadata Synchronization
Automatically constructs and synchronizes five custom product metafields to Shopify Admin via GraphQL `metafieldsSet`:
1. `custom.brand`: Dynamic lookup for `APSS Brand` field data from Item.
2. `custom.manufacture_number`: `custom.manufacture_number` uses `Item Reference."Reference No."` where `Reference Type = Customer`, based on the confirmed SCC business mapping.
3. `custom.uom`: Mapped from `Item."Base Unit of Measure"`.
4. `custom.incoterms`: Fixed default text value `'EXW'`.
5. `custom.lead_time`: Calculated from `Item."Lead Time Calculation"` as integer number of days.

> [!NOTE]
> **Native Shopify Product Description:** Native Shopify product description (body_html) is handled out-of-the-box by the Standard Microsoft Shopify Connector (`Marketing Text` / `Item.Description`). No custom `custom.description` metafield is synchronized by custom code to prevent redundant metadata duplication in Shopify Admin.

> [!IMPORTANT]
> `custom.manufacture_number` uses `Item Reference."Reference No."` where `Reference Type = Customer`, based on the confirmed SCC business mapping. Where an item possesses multiple Customer Reference records (e.g. across multiple Customer Nos), selecting the primary Customer No. is an open business clarification for Kathy/Lead. `FindFirst()` is used as technical fallback behavior, NOT a confirmed final business rule.

### Product Title
- Product title logic is formatted as `[Brand] - [Vendor Item No.] - [Description]` using `GetProductNumber(Item)` which returns `Item."Vendor Item No."`.
- Product title formatting is completely decoupled from `custom.manufacture_number` (which uses `Item Reference."Reference No."`).

### Pricing & Unit of Measure (UOM)
- Standard Microsoft Shopify Connector pricing calculation remains completely untouched.
- `custom.uom` maps `Item."Base Unit of Measure"`. Sales Unit of Measure (`Item."Sales Unit of Measure"`) is handled natively by the standard Connector.
- The controlled UOM comparison demonstrated a 10× quantity/price scaling effect consistent with the configured `BOX = 10 EA` conversion. This confirms the UOM scaling behavior observed in the test; it does not introduce or modify custom UOM conversion logic.
- No custom price override logic is implemented.

---

## 4. High-Level Architecture

```
Business Central Item
        |
        +--> Add Items (Report 30106) --> APSS Approved & Image Gate --> Shopify Product Creation
        |
        +--> Existing Product Sync (Codeunit 30178) --> APSS Approved & Image Gate --> Shopify Product Update
        |
        +--> Readiness Validation (Codeunit 90301) --> Item List Updates
        |
        +--> Metafield Sync (Codeunit 90302) --> GraphQL metafieldsSet --> Shopify Metafields
```

---

## 5. Phase Scope

### Implemented (Updated Phase 1)
- `APSS Approved` approval gate (Field 50001)
- Image presence gate (`Picture.Count() > 0`) for Add Items and Sync Products
- Dynamic Item Shopify Readiness calculation and page actions
- Automated 5-metafield synchronization (`brand`, `manufacture_number`, `uom`, `incoterms`, `lead_time`)
- Dynamic RecordRef/FieldRef field resolution

### Deferred (Phase 2 Backlog)
- `custom.price_valid_until` (Deactivated in Phase 1)
- Datasheet / Product Specs attachments
- Custom UOM fallback / unit conversion logic
- Custom price override engine

---

## 6. Setup & Development

### Prerequisites
- Microsoft Dynamics 365 Business Central (BC 28 or compatible sandbox environment)
- Standard Microsoft Shopify Connector (`Microsoft.Integration.Shopify`)
- AL Language Extension for Visual Studio Code (`v17`)
- Downloaded package dependencies in `.alpackages/` (`System`, `Base Application`, `Microsoft Shopify Connector`)

### Build Instructions
1. Open the project root directory in VS Code.
2. Ensure symbol dependencies exist in `.alpackages`.
3. Compile using AL Compiler (`alc.exe`):
   ```cmd
   alc.exe /project:"." /packagecachepath:".alpackages" /out:"APSS_APSS Shopify Enhancements_1.0.0.0.app"
   ```

### Deployment Configuration
Deployment to Business Central sandbox (`June9`) via AL: Publish or `launch.json`:
```json
{
  "environmentType": "Sandbox",
  "environmentName": "June9",
  "authenticator": "UserPassword",
  "schemaUpdateMode": "Synchronize"
}
```

---

## 7. Repository Structure

```
APSS_Shopify/
├── .alpackages/                        # Compiled symbol packages for dependencies
├── .vscode/                            # VS Code configuration (launch.json)
├── docs/
│   └── PHASE_1.md                      # Detailed Phase 1 technical, historical & verification doc
├── src/
│   ├── AddItemImageGate.ReportExt.al   # Image & Approval Gate for Add Items report
│   ├── ItemListShopify.PageExt.al      # Readiness fields and actions on Item List
│   ├── ItemShopifyReady.TableExt.al    # Readiness custom fields on Item table
│   ├── ShopifyEnhancements.PermissionSet.al # Extension permissions
│   ├── ShopifyProductTitle.Codeunit.al  # Title formatting & GetCustomerItemReference helper
│   ├── ShopifyReadinessMgt.Codeunit.al  # Readiness validation logic
│   └── ShopifySyncEvents.Codeunit.al    # Sync filters & automatic 5-metafield sync
├── app.json                            # AL Extension manifest
└── README.md                           # Main GitHub repository README
```

---

## 8. Detailed Documentation

For complete technical design, detailed execution flows, file-by-file object listings, testing strategy, UOM investigation, historical test logs, and current E2E evidence breakdown, refer to the detailed implementation document:

👉 [**Phase 1 Technical, Historical & Verification Document**](docs/PHASE_1.md)

---

## 9. Testing & Validation Summary

- **Static Code Review:** Passed (7 production AL files verified).
- **Build Status:** Passed (`0` errors, `0` warnings with Microsoft AL Compiler). Package generated successfully.
- **Controlled Single-Item E2E (Current Code):** **PASS** (Verified for current code after removing `custom.description` targeting `APSS-TEST-META-001` / `REF-CUST-99001` / Shopify Product ID `16162851422511`).
- **Multi-Reference Selection:** Pending business rule confirmation for items with multiple Customer Nos.

> [!NOTE]
> **Controlled E2E vs. Production Readiness:** The controlled E2E confirms the tested current implementation. Production readiness remains CONDITIONAL because the business selection rule for Items with multiple Customer References is still pending confirmation.
