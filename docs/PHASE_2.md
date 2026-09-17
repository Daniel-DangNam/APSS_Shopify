# PHASE 2 — Comprehensive Technical, Functional & Verification Document

---

## 1. Document Purpose

This document serves as the single authoritative, detailed technical and functional reference for **Phase 2** of the **APSS Shopify Enhancements** extension for Microsoft Dynamics 365 Business Central (BC 28) and Microsoft Shopify Connector. It details the complete architecture, pricing engine integration, state management evolution from in-memory cache to persistent staging database (`Table 90306`), diagnostic logging infrastructure (`Table 90305` & `Page 90305`), UOM validation, and complete E2E runtime evidence from both Business Central Sandbox June9 and Shopify Storefront/Admin.

---

## 2. Phase 2 History & Scope Evolution

### 2.1 Initial Phase 2 Approach (Option A - In-Memory Cache)
- **Concept:** Subscribed to `Codeunit 7020 "Sales Line - Price"` (`OnAfterSetPrice`) to capture `PriceListLine."Ending Date"`. Cached the captured ending date in a `SingleInstance` codeunit dictionary keyed by `Item No.`.
- **Limitation Identified:** In Business Central, NST background jobs, Job Queue executions, and Web Service calls execute in separate NST sessions. A `SingleInstance` in-memory dictionary is isolated per session and lost across background session boundaries, causing `Ending Date` to return `0D` during async Shopify Sync runs.

### 2.2 Pricing Engine Architecture Discovery (Legacy vs. New Pricing)
- **Discovery:** Business Central Sandbox June9 operates on the **Legacy Pricing Experience** (`Sales Prices` Table 7002 / `Codeunit 7000 "Sales Price Calc. Mgt."`), rather than exclusively the New Pricing Experience (`Codeunit 7020`).
- **Solution:** Integrated subscribers for both pricing engines:
  - `CaptureLegacyBestSalesPriceEndingDate` (`Codeunit 7000 "Sales Price Calc. Mgt."`, event `OnAfterCalcBestUnitPrice`) for Legacy Pricing.
  - `CaptureSalesPriceEndingDate` (`Codeunit 7020 "Sales Line - Price"`, event `OnAfterSetPrice`) for New Pricing.

### 2.3 Final Persistent Staging Architecture (Table 90306)
- **Persistent DB Staging:** Replaced in-memory dictionary caching with a dedicated persistent database staging table: **`APSS Item Price Ending Date` (`Table 90306`)**.
- **Session Safety & Purge Cycle:** Staging records are keyed by `Item No.` and `Shop Code`, storing `Last Session ID` and `Has Variant Conflict`. Staging data for each `Shop Code` is automatically purged at the start of every product sync run in `FilterProductsWithoutImageOnSync`.

---

## 3. Final Business Requirements & Specifications

### 3.1 Unit Price Calculation Override (Quantity = 1.0)
- **Requirement:** Standard Microsoft Shopify Connector calculates variant prices using `Quantity = 0.0`. In BC pricing logic, minimum quantity thresholds on Sales Price lines require `Quantity = 1.0` to evaluate valid sales prices (e.g. `$123.45` LCY).
- **Implementation:** `CalculateUnitPriceWithQuantityOne` subscribes to `Shpfy Product Events` -> `OnBeforeCalculateUnitPrice`. It executes a temporary quote calculation with `Quantity = 1.0`, capturing the exact unit price (`$123.45` LCY -> converted to `$158.902` SGD via BC Shop currency exchange rate `1.287177`).

### 3.2 Product Price Ending Date (`custom.price_valid_until`)
- **Source of Truth:** `Sales Price."Ending Date"` (Legacy) or `Price List Line."Ending Date"` (New Pricing).
- **Target Metafield:** `custom.price_valid_until`
- **Type:** `date` (ISO format `YYYY-MM-DD`, e.g., `2026-09-30`).
- **Conflict Handling:** If an item has multiple variants with differing ending dates, `Has Variant Conflict` is set to `true` in Table 90306, and `price_valid_until` is omitted to prevent misleading date representation on Shopify.

### 3.3 Diagnostic Log Infrastructure (`Table 90305` & `Page 90305`)
- **Requirement:** Retain operational diagnostic logging for long-term production maintenance and troubleshooting.
- **Table:** `APSS Diagnostic Log` (`Table 90305`) records `Session ID`, `Context`, `Item No.`, `Shop Code`, `Calculated Price`, `Captured Ending Date`, `Error Text`, and execution `Details`.
- **Page:** `APSS Diagnostic Logs` (`Page 90305`) provides an admin UI to inspect diagnostic logs in real time.

### 3.4 Unit of Measure (UOM) Verification
- **Rule:** `custom.uom` strictly maps `Item."Base Unit of Measure"`.
- **Verification:** Tested Base UOM (`EA`) vs. Sales UOM (`BOX`). Verified that `custom.uom` receives `EA` without altering `Item."Sales Unit of Measure"` or corrupting pricing.

### 3.5 Datasheet / Product Specs (Deferred)
- **Status:** **DEFERRED / OUT OF CURRENT SCOPE**
- **Reason:** Business Central document attachments are internal BLOBs requiring authentication. Public URL generation and file hosting strategy (Shopify Files API vs Cloud Storage) require business/tech lead approval.

---

## 4. Current Production Implementation

The Phase 2 extension is implemented across 10 AL source files under `src/`:

| File Path | Object Type & ID | Object Name | Primary Responsibility |
| :--- | :--- | :--- | :--- |
| [`src/APSSItemPriceEndingDate.Table.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSItemPriceEndingDate.Table.al) | `Table 90306` | `APSS Item Price Ending Date` | Persistent staging DB storing captured ending dates per Item & Shop |
| [`src/APSSDiagnosticLog.Table.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSDiagnosticLog.Table.al) | `Table 90305` | `APSS Diagnostic Log` | Operational diagnostic logging table |
| [`src/APSSDiagnosticLogs.Page.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSDiagnosticLogs.Page.al) | `Page 90305` | `APSS Diagnostic Logs` | Admin page UI for inspecting diagnostic logs |
| [`src/ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al) | `Codeunit 90302` | `APSS Shopify Sync Events` | Pricing override, Legacy & New pricing subscribers, Staging DB & Metafields sync |
| [`src/ShopifyProductTitle.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyProductTitle.Codeunit.al) | `Codeunit 90300` | `APSS Shopify Product Title` | Product title formatting, APSS Approved check, Customer Reference lookup |
| [`src/ShopifyReadinessMgt.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyReadinessMgt.Codeunit.al) | `Codeunit 90301` | `APSS Shopify Readiness Mgt.` | Evaluates item readiness status |
| [`src/AddItemImageGate.ReportExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/AddItemImageGate.ReportExt.al) | `ReportExtension 90300` | `APSS Add Item Image Gate` | Image & Approval Gate for Add Items report |
| [`src/ItemShopifyReady.TableExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemShopifyReady.TableExt.al) | `TableExtension 90300` | `APSS Item Shopify Ready` | Readiness fields on Item table |
| [`src/ItemListShopify.PageExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemListShopify.PageExt.al) | `PageExtension 90300` | `APSS Item List Shopify` | Readiness fields and refresh actions on Item List page |
| [`src/ShopifyEnhancements.PermissionSet.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyEnhancements.PermissionSet.al) | `PermissionSet 90300` | `APSS SHOPIFY ENH` | Permission set granting RIMD permissions for staging & log tables |

---

## 5. Architecture & Execution Flow

### Unit Price Calculation & Staging Flow
```
Shpfy Product Export / Sync
  └─► OnBeforeCalculateUnitPrice (CalculateUnitPriceWithQuantityOne)
        ├─► Bind ShpfyUpdatePriceSource
        ├─► TryCalculatePrice(Item, VariantCode, UnitOfMeasure, Shop, Catalog)
        │     ├─► Create Temp Sales Header (Currency = Shop Currency, Date = WorkDate)
        │     └─► Validate Temp Sales Line (Quantity = 1.0)
        │           ├─► Trigger Legacy Pricing (CU 7000 OnAfterCalcBestUnitPrice) ──► Capture CurrentCalcEndingDate & CurrentCalcBestUnitPrice
        │           └─► Trigger New Pricing (CU 7020 OnAfterSetPrice)              ──► Capture CurrentCalcEndingDate & CurrentCalcBestUnitPrice
        ├─► Unbind ShpfyUpdatePriceSource
        ├─► RecordEndingDateForVariant(ItemNo, ShopCode, VariantCode, EndingDate)
        │     └─► Insert / Modify APSS Item Price Ending Date (Table 90306)
        └─► Return Unit Price ($158.902 SGD)
```

### Metafields Population Flow
```
OnBeforeUpdateProductMetafields / OnAfterInsertShopifyProduct
  └─► PopulateProductMetafieldRecords(ShopifyProduct)
        ├─► custom.brand = GetBrandName(Item)
        ├─► custom.manufacture_number = GetCustomerItemReference(Item)
        ├─► custom.uom = Item."Base Unit of Measure"
        ├─► custom.incoterms = 'EXW'
        ├─► custom.lead_time = Integer Days
        └─► custom.price_valid_until = Format(EndingDate, 'YYYY-MM-DD')  <-- fetched from Table 90306
              └─► Shpfy Metafield (Table 30142)
                    └─► GraphQL metafieldsSet
```

---

## 6. E2E Verification Evidence Summary

### Controlled E2E Verification (Item APSS-TEST-PRICE-002)

- **Environment:** Business Central Sandbox `June9`
- **Shop Code:** `APSS SHOP` (Currency: `SGD`, Exchange Rate: `1.287177`)
- **Test Item:** `APSS-TEST-PRICE-002`
- **Master Data:**
  - Base Unit Price LCY = `$123.45`
  - Sales Price Ending Date = `2026-09-30`
  - Base Unit of Measure = `EA`
  - Brand = `ALLEN-BRADLEY`
  - Customer Item Reference = `REF-PRICE-002`
  - Lead Time Calculation = `10D`
  - APSS Approved = `Yes`
  - Picture = Present

### Verified Evidence Results

| Component | Target Location | Expected Value | Verified Actual Value | Status |
|---|---|---|---|---|
| **Price Valid Until** | Shopify Storefront / Admin | `September 30, 2026` (`2026-09-30`) | `September 30, 2026` | **PASS** |
| **Unit Price** | Shopify Variant Price | `158.902` SGD (`123.45` * `1.287177`) | `158.902` SGD | **PASS** |
| **Brand** | Shopify Product Metafield | `ALLEN-BRADLEY` | `ALLEN-BRADLEY` | **PASS** |
| **Manufacture Number** | Shopify Product Metafield | `REF-PRICE-002` | `REF-PRICE-002` | **PASS** |
| **UOM** | Shopify Product Metafield | `EA` | `EA` | **PASS** |
| **Incoterms** | Shopify Product Metafield | `EXW` | `EXW` | **PASS** |
| **Lead Time** | Shopify Product Metafield | `10` | `10` | **PASS** |

---

## 7. Final Status Summary

| Item | Status |
| :--- | :--- |
| **Implementation** | **PASS** |
| **Code Review** | **PASS** |
| **AL Build (`alc.exe`)** | **PASS** (`0` errors, `0` warnings) |
| **Persistent Staging (Table 90306)** | **PASS** |
| **Diagnostic Logging (Table 90305 / Page 90305)** | **PASS** |
| **Shopify E2E Runtime Validation** | **PASS** |
| **Production Readiness** | **READY FOR DEPLOYMENT** |
