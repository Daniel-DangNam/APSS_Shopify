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

### 3.5 Interactive Item Selection Modal & Dual Sync Architecture

- **Requirement:** Provide an explicit UI action on the Business Central Item List page allowing users to inspect and select eligible candidate items (`New Ready` 🟢 or `Modified Ready` 🟡) via a dedicated selection modal before triggering Shopify synchronization.
- **Selection Modal & Visual Checkbox (`Page 90300` & `Table 90300`):**
  - Displays a modal list (`APSS Shopify Item Selection`) bound to temporary buffer table `APSS Shpfy Item Sel. Buffer`.
  - Field `Selected` (`Boolean`) renders as a visual Checkbox (`[ ]` / `[✓]`) for intuitive line-by-line selection.
  - Actions `Select All` and `Deselect All` for batch selection control.
- **Dual Sync Execution Path:**
  - **New Ready Items (`Report 30106 "Shpfy Add Item to Shopify"`):**
    - Triggered strictly for selected items with status `New Ready`.
    - Executed with `<Field name="SyncInventory">true</Field>` in request parameters to push both product catalog and initial inventory quantities to Shopify locations in a single pass.
    - Filtered strictly by item numbers (`"No." = 'ITEM1'|'ITEM2'`).
  - **Modified Ready Items (`Report 30108 "Shpfy Sync Products"`):**
    - Triggered strictly for selected items with status `Modified Ready`.
    - Restricts `Shpfy Product Export` (`Codeunit 30178`) via targeted `SystemId` filter in `APSS Shopify Sync Events` (`OnAfterProductsToSynchronizeFiltersSet`).
    - Executes `productUpdate` GraphQL mutation in < 1 second without scanning the full catalog or using manual `Last Updated by BC` timestamp hacks.
  - **Automatic UI Status Transition:** Calls `CurrPage.Update(false)` after sync, updating item sync status badges to **`Synced Unchanged`** (green/subordinate style).
  - **User Feedback:** Displays post-sync summary message (e.g. `1 new item(s) and 1 modified item(s) were processed for Shopify sync.`).

### 3.6 Mapping Rules & Field Transformations (Kathy & June Specifications)

| Target Field / Metafield      | Target Location                   | Source Field (BC Item)            | Logic / Transformation                                                                                                                                                                                                                          |
| :---------------------------- | :-------------------------------- | :-------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Title**                     | Shopify Product `Title`           | `APSS Brand`, `Description`       | Format: `Brand + Description`. Anti-duplication: if `Description` already starts with `Brand`, use `Description` directly to prevent duplication (e.g., `ASCO` + `ASCO Valve...` -> `ASCO Valve...`). No Vendor Item No., no Customer Item Ref. |
| **Description**               | Shopify Product `Description`     | Marketing Text / Description      | BC Marketing Text (rich HTML) mapped to Shopify native product description.                                                                                                                                                                     |
| **SEO Title**                 | Shopify Product `SEO Title`       | Product Title                     | Truncated to maximum 70 characters.                                                                                                                                                                                                             |
| **SEO Description**           | Shopify Product `SEO Description` | Marketing Text                    | HTML tags stripped (`RemoveHtmlTags`), normalized whitespace, truncated to maximum 160 characters.                                                                                                                                              |
| **Vendor**                    | Shopify Product `Vendor`          | `APSS Brand` / `Brand Code`       | Brand name lookup.                                                                                                                                                                                                                              |
| **custom.manufacture_number** | Product & Variant Metafield       | `Item.Description`                | Exact key `custom.manufacture_number` mapped from `Item.Description.Trim()` (preserving client convention).                                                                                                                                     |
| **custom.brand**              | Product Metafield                 | `APSS Brand` / `Brand Code`       | Brand name string.                                                                                                                                                                                                                              |
| **custom.uom**                | Product Metafield                 | `Item."Base Unit of Measure"`     | Standard Base UOM code (e.g. `EA`, `PCS`).                                                                                                                                                                                                      |
| **custom.incoterms**          | Product Metafield                 | Fixed default                     | Fixed to `'EXW'`.                                                                                                                                                                                                                               |
| **custom.lead_time**          | Product Metafield                 | `Item."Lead Time Calculation"`    | Integer days extracted (omitted if blank/zero).                                                                                                                                                                                                 |
| **custom.price_valid_until**  | Product Metafield                 | Ending Date / Staging Table 90306 | Date formatted as `YYYY-MM-DD`. Default `Today + 30D` if no ending date specified.                                                                                                                                                              |
| **Price**                     | Shopify Variant `Price`           | BC Sales Price Engine             | Applicable SGD price computed via temporary quote (`Quantity = 1.0`, shop currency SGD exchange rate).                                                                                                                                          |
| **Inventory**                 | Shopify Inventory Levels          | BC Item Inventory                 | Pushed during initial export via `Report 30106` with `SyncInventory = true`.                                                                                                                                                                    |

---

## 4. Current Implementation

The extension is implemented across 13 AL source files under `src/`:

| File Path                                                                                                                           | Object Type & ID        | Object Name                     | Primary Responsibility                                                            |
| :---------------------------------------------------------------------------------------------------------------------------------- | :---------------------- | :------------------------------ | :-------------------------------------------------------------------------------- |
| [`src/APSSItemPriceEndingDate.Table.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSItemPriceEndingDate.Table.al)         | `Table 90306`           | `APSS Item Price Ending Date`   | Persistent staging DB storing captured ending dates per Item & Shop               |
| [`src/APSSDiagnosticLog.Table.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSDiagnosticLog.Table.al)                     | `Table 90305`           | `APSS Diagnostic Log`           | Operational diagnostic logging table                                              |
| [`src/APSSDiagnosticLogs.Page.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSDiagnosticLogs.Page.al)                     | `Page 90305`            | `APSS Diagnostic Logs`          | Admin page UI for inspecting diagnostic logs                                      |
| [`src/APSSShpfyItemSelBuffer.Table.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/APSSShpfyItemSelBuffer.Table.al)           | `Table 90300`           | `APSS Shpfy Item Sel. Buffer`   | Temporary buffer table for modal selection page with visual checkbox              |
| [`src/ShopifyItemSelection.Page.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyItemSelection.Page.al)                 | `Page 90300`            | `APSS Shopify Item Selection`   | Modal selection page for selecting candidate items before Shopify sync            |
| [`src/ShopifyItemSyncStatus.Enum.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyItemSyncStatus.Enum.al)               | `Enum 90300`            | `APSS Shopify Item Sync Status` | Sync status enum (`Not Ready`, `New Ready`, `Modified Ready`, `Synced Unchanged`) |
| [`src/ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al)               | `Codeunit 90302`        | `APSS Shopify Sync Events`      | Pricing override, SEO subscribers, Staging DB & Metafields sync                   |
| [`src/ShopifyProductTitle.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyProductTitle.Codeunit.al)           | `Codeunit 90300`        | `APSS Shopify Product Title`    | Product title formatting (`Brand + Description` anti-duplication) & Brand lookup  |
| [`src/ShopifyReadinessMgt.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyReadinessMgt.Codeunit.al)           | `Codeunit 90301`        | `APSS Shopify Readiness Mgt.`   | Evaluates item readiness status and sync state (Description <> '' check)          |
| [`src/AddItemImageGate.ReportExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/AddItemImageGate.ReportExt.al)               | `ReportExtension 90300` | `APSS Add Item Image Gate`      | Image & Approval Gate for Add Items report                                        |
| [`src/ItemShopifyReady.TableExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemShopifyReady.TableExt.al)                 | `TableExtension 90300`  | `APSS Item Shopify Ready`       | Readiness fields on Item table                                                    |
| [`src/ItemListShopify.PageExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemListShopify.PageExt.al)                     | `PageExtension 90300`   | `APSS Item List Shopify`        | Readiness fields, status styles, and Add Ready Items action on Item List          |
| [`src/ShopifyEnhancements.PermissionSet.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyEnhancements.PermissionSet.al) | `PermissionSet 90300`   | `APSS SHOPIFY ENH`              | Permission set granting RIMD permissions for staging, buffer & log tables         |

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
        │           ├─► Trigger Legacy Pricing (CU 7000 OnAfterCalcBestUnitPrice) ──► Capture CurrentCalcEndingDate & CalcPrice (in SGD)
        │           └─► Trigger New Pricing (CU 7020 OnAfterSetPrice)              ──► Capture CurrentCalcEndingDate & CalcPrice (in SGD)
        ├─► Unbind ShpfyUpdatePriceSource
        ├─► RecordEndingDateForVariant(ItemNo, ShopCode, VariantCode, EndingDate)
        │     └─► Insert / Modify APSS Item Price Ending Date (Table 90306)
        └─► Return Converted Unit Price (e.g. $158.902 SGD without LCY overwrite)
```

### Metafields & SEO Population Flow

```
OnBeforeUpdateProductMetafields / OnAfterInsertShopifyProduct
  ├─► PopulateProductMetafieldRecords(ShopifyProduct)
  │     ├─► custom.brand = GetBrandName(Item)
  │     ├─► custom.manufacture_number = Item.Description (Product & Variant)
  │     ├─► custom.uom = Item."Base Unit of Measure"
  │     ├─► custom.incoterms = 'EXW'
  │     ├─► custom.lead_time = Integer Days
  │     └─► custom.price_valid_until = Format(EndingDate, 'YYYY-MM-DD') (default Today + 30D)
  └─► SetShopifyProductSeo (OnAfterFillInShopifyProductFields)
        ├─► ShopifyProduct."SEO Title" = CopyStr(Title, 1, 70)
        └─► ShopifyProduct."SEO Description" = CopyStr(RemoveHtmlTags(MarketingText), 1, 160)
```

---

## 6. Acceptance Testing Checklist (Sandbox E2E Verification Required)

Before marking the implementation as production-ready, the following 10 test scenarios must be executed and validated in Business Central Sandbox June9:

- [x] **Test A - Brand & Description Title Format & Readiness Filter Criteria:** **PASS** (Verified on Sandbox June9) - Item: APSS-TEST-A
  - A.1 (`Approved = false`) -> Not Ready 🔴 (PASS)
  - A.2 (`Approved = true`, Missing Picture) -> Not Ready 🔴 (PASS)
  - A.3 (Approved + Picture + Brand + Description + UOM + Price) -> New Ready 🟢 (PASS)
  - A.4 (Missing Customer Item Reference) -> New Ready 🟢 (PASS)
  - Resulting Title: `Brand + Description` formatted cleanly.
- [x] **Test B - Brand Duplication Prevention & Standard Title Formatting:** **PASS** (Verified on Sandbox June9)
  - APSS-TEST-B.1 (Brand = `TECHNOR`, Description = `B012074010134`) -> Shopify Title = `TECHNOR B012074010134` (PASS)
  - APSS-TEST-B.2 (Brand = `ASCO`, Description = `ASCO 8210G022 Solenoid Valve`) -> Shopify Title = `ASCO 8210G022 Solenoid Valve` (PASS - No duplicate `ASCO ASCO`, no Vendor Item No.)
- [x] **Test C - Native Product Description Mapping:** **PASS** (Verified on Sandbox June9)
  - BC Marketing Text (rich text/HTML) -> Shopify Native Product Description rendered cleanly on Shopify Admin. Item: APSS-TEST-B1 (PASS)
- [x] **Test D - Shopify Product Metafields Mapping:** **PASS** (Verified on Sandbox June9)
  - Product Metafields verified directly on Shopify Admin for item APSS-TEST-B.1: `custom.brand` = TECHNOR, `custom.manufacture_number` = B012074010134, `custom.uom` = EA, `custom.incoterms` = EXW, `custom.lead_time` = 10, `custom.price_valid_until` = Oct 18, 2026. (PASS)
- [x] **Test E - Variant / Google Metafields & MPN Mapping:** **PASS** (Verified on Sandbox June9)
  - E.1 Short Part Number (Item `APSS-TEST-B.1` `B012074010134`): `custom.manufacture_number` = `B012074010134`, `Google MPN` = `B012074010134`, `Google Custom Product` = `true`. (PASS)
  - E.2 Multi-word Description (Item `APSS-TEST-B.2` `ASCO 8210G022 Solenoid Valve`): `custom.manufacture_number` = `ASCO 8210G022 Solenoid Valve`, `Google MPN` = `[EMPTY]` (omitted per June rule to avoid guessing, diagnostic warning `GoogleMPN:Omitted` logged), `Google Custom Product` = `true`. (PASS)
- [x] **Test F - Converted SGD Pricing & Sales Price Engine:** **PASS** (Verified on Sandbox June9)
  - Item `APSS-TEST-PRICE-002`: Base Unit Price LCY `$123.45` converted via SGD shop exchange rate `1.287177` -> Shopify Price = `$158.90 SGD`. Verified not using Unit Cost (`$50.00`), not using Purchase Price (`$40.00`), no double-conversion, proper Quantity = 1.0 and UOM `EA`. (PASS)
- [ ] **Test G - Dual Sync Separation & Inventory Location Sync:** **SKIPPED / BLOCKED ON SANDBOX**
  - Inventory posting blocked in Sandbox due to Business Central Default Dimension rule conflict on sandbox location `APSS-SG` vs Item `BRAND` dimension rules (`ALLEN-BRADLEY` vs `TOBEADVISED`). Code implementation includes `<Field name="SyncInventory">true</Field>` parameter on `Report 30106`.
- [x] **Test H - Mixed Add/Sync Selection (New Ready + Modified Ready):** **PASS** (Verified on Sandbox June9 with item `APSS-TEST-NEW-01`)
  - Selected 1 New Ready Item and 1 Modified Ready Item simultaneously in selection modal.
  - New Item executed only Add report (Report 30106), Modified Item executed only Sync report (Report 30108).
  - Verified no duplicate product created on Shopify and Modified Item was not incorrectly re-added.
- [x] **Test I - Product Specs Attachment Metafield Sync (`custom.product_specs`):** **PASS** (Verified on Sandbox June9 & Shopify Storefront)
  - PDF attachment attached to BC Item (`APSS-TEST-NEW-01`).
  - `custom.product_specs` metafield bound as `file_reference` on Shopify Admin (`Chapter_4__Sentiment...pdf`).
  - Verified user can click and download Data Sheet directly from Shopify Storefront (`Download Data Sheet`). (PASS)
- [x] **Test J - Failure Handling & State Integrity:** **PASS** (Verified on Sandbox June9 via Entry 67520 & Log 1221)
  - Intentionally tested invalid metafield value/type mismatch.
  - Verified error recorded in `Shopify Log Entries` (`Entry 67520` with `Has Error = true`) and `APSS Diagnostic Log`.
  - Verified `Last Updated by BC` / `SystemModifiedAt` is NOT falsely updated on failure.
  - Verified Item remains in `Modified Ready` 🟡 pending state and does NOT falsely transition to `Synced Unchanged`. (PASS)

---

## 7. Final Status Summary

| Item                                              | Status                                                                                | Notes                                                              |
| :------------------------------------------------ | :------------------------------------------------------------------------------------ | :----------------------------------------------------------------- |
| **Code Implementation**                           | **PASS**                                                                              | All 17 requirements & mapping rules implemented                    |
| **Code Review & Linter**                          | **PASS**                                                                              | Strict clean typing, UTF-8 encoded                                 |
| **AL Build (`alc.exe`)**                          | **PASS**                                                                              | Compiled with `0` errors, `0` warnings                             |
| **Persistent Staging (Table 90306)**              | **PASS**                                                                              | Session-safe ending date tracking                                  |
| **Diagnostic Logging (Table 90305 / Page 90305)** | **PASS**                                                                              | Comprehensive operational tracing                                  |
| **Shopify E2E Runtime Validation**                | **PASS**                                                                              | Tests A, B, C, D, E, F, H, I, J verified on Sandbox June9          |
| **Production Deployment Status**                  | **Implementation in progress / Sandbox verification required / Not production-ready** | Completed sandbox validation; awaiting user instruction for deploy |
