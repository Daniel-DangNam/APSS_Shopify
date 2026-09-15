# PHASE 1 — Comprehensive Technical, Functional & Verification Document

---

## 1. Document Purpose

This document serves as the single authoritative, detailed technical and functional reference for **Phase 1** of the **APSS Shopify Enhancements** extension for Microsoft Dynamics 365 Business Central (BC 28) and Microsoft Shopify Connector. It details the complete project history, evolution of scope, current production implementation, complete execution flows, UOM investigation analysis, and both **Historical Original Phase 1 Evidence** and **Current Updated Phase 1 Evidence**.

---

## 2. Phase 1 History & Scope Evolution

### 2.1 Original Phase 1
- **Focus:** Image presence gates for product publishing, basic readiness checking on Item records, and initial 6-metafield synchronization (`brand`, `manufacture_number`, `description`, `uom`, `incoterms`, `lead_time`).
- **Initial Metafield Mapping:** `custom.manufacture_number` was mapped from `Item."Vendor Item No."` as a temporary test placeholder, and `custom.description` mapped `Item.Description`.

### 2.2 Updated Phase 1
- **APSS Approved Requirement:** Lead confirmation established `Item."APSS Approved"` (Field 50001, Boolean) as the sole approval source of truth across both product creation (Add Items) and product update (Sync Products) flows.
- **Confirmed Customer Reference Mapping:** Stakeholder confirmation (Kathy) based on actual SCC data established that `custom.manufacture_number` must use `Item Reference."Reference No."` where `Reference Type = Customer`.
- **Native Product Description Alignment:** Clarified that Shopify native Product Description (body_html) is handled out-of-the-box by the Standard Microsoft Shopify Connector (`Marketing Text` / `Item.Description`). The redundant custom product metafield `custom.description` was removed from custom code.

### 2.3 Final Integrated Phase 1
- **Scope = Image Presence Gates + APSS Approved Requirement + Confirmed Customer Item Reference Mapping + 5 Custom Product Metafields + Dynamic Shopify Readiness Validation.**

---

## 3. Final Business Requirements

### 3.1 APSS Approved Gate
- **Source of Truth:** `Item."APSS Approved"` (Field 50001, Boolean).
- **Rule:**
  - `APSS Approved = false` → Item is strictly excluded from Add Items (new product creation) and Sync Products (existing product update).
  - `APSS Approved = true` → Item is eligible when image presence and required master data are satisfied.
- **Exclusions:** `Item.Blocked` is NOT used as an approval source. Native Business Central Approval Workflows (Table 454 `Approval Entry`) are NOT used as an approval source.

### 3.2 Image Gate
- **Add Items Flow:** Requires `Picture.Count() > 0`. Items lacking images are filtered prior to product creation using a guaranteed no-match filter (`'APSS_NO_IMAGE_MATCH'`).
- **Existing Product Sync Flow:** Requires `Picture.Count() > 0`. Existing products mapped to items without images are excluded from sync.
- **Option C Error Behavior:** Items lacking approval or images are filtered out silently without writing error entries to the Shopify Log.

### 3.3 Shopify Readiness Validation
- **Required Conditions (`APSS Shopify Ready = true`):**
  1. `APSS Approved = true`
  2. `Picture` exists (`Picture.Count() > 0`)
  3. `Customer Item Reference No.` exists (`GetCustomerItemReference(Item) <> ''`)
  4. `Brand` exists (`GetBrandName(Item) <> ''`)
  5. `Base Unit of Measure` exists (`Item."Base Unit of Measure" <> ''`)
- **Optional Fields:** `Description`, `Incoterms`, `Lead Time`.
- **Non-Blocking Fields:** `Unit Price`, `Item.Blocked`.
- **Readiness vs. Product Title Audit:**
  - `GetProductNumber(Item)` returns `Item."Vendor Item No."` and is used solely for Product Title formatting (`[Brand] - [Vendor Item No.] - [Description]`).
  - `Vendor Item No.` does not contain meaningful Manufacturer Part Number information.
  - Shopify Readiness and product metafield synchronization evaluate `GetCustomerItemReference(Item)` (`Item Reference."Reference No."` where `Reference Type = Customer`). Readiness validation is aligned with the confirmed Customer Reference No. mapping.

### 3.4 Five Custom Product Metafields (and Native Product Description)

| Metafield | Namespace | Target Field Name | Source Field / Logic | Type |
| :--- | :--- | :--- | :--- | :--- |
| `custom.brand` | `custom` | `brand` | Dynamic `APSS Brand` field lookup | `single_line_text_field` |
| `custom.manufacture_number` | `custom` | `manufacture_number` | `Item Reference."Reference No."` where `Reference Type = Customer` (confirmed SCC business mapping) | `single_line_text_field` |
| `custom.uom` | `custom` | `uom` | `Item."Base Unit of Measure"` | `single_line_text_field` |
| `custom.incoterms` | `custom` | `incoterms` | Fixed default text `'EXW'` | `single_line_text_field` |
| `custom.lead_time` | `custom` | `lead_time` | Calculated from `Item."Lead Time Calculation"` (integer days) | `number_integer` |

> [!NOTE]
> **Native Shopify Product Description:** Native Shopify product description (body_html) is handled out-of-the-box by the Standard Microsoft Shopify Connector (`Marketing Text` / `Item.Description`). No custom `custom.description` metafield is synchronized by custom code to prevent redundant metadata duplication in Shopify Admin.

> [!IMPORTANT]
> `custom.manufacture_number` uses `Item Reference."Reference No."` where `Reference Type = Customer`, based on the confirmed SCC business mapping.
> 
> **Multi-Customer Reference Selection Clarification:** When an Item possesses multiple Customer Reference entries in Table 5777 (e.g. across different Customer Nos, Variant Codes, or Date Ranges), current technical implementation retrieves the first matching record via `FindFirst()`. Establishing a specific Customer No. filter or deterministic selection rule for multi-reference items is documented as an open business clarification for Kathy/Lead. `FindFirst()` is a technical fallback behavior, NOT a confirmed final business rule.

### 3.5 Unit of Measure (UOM)
- `custom.uom` maps `Item."Base Unit of Measure"`.
- The controlled UOM comparison demonstrated a 10× quantity/price scaling effect consistent with the configured `BOX = 10 EA` conversion. This confirms the UOM scaling behavior observed in the test; it does not introduce or modify custom UOM conversion logic.
- Standard Connector handles Sales Unit of Measure (`Item."Sales Unit of Measure"`).

### 3.6 Incoterms
- Populated as fixed text `'EXW'`.

### 3.7 Lead Time
- Calculated dynamically as `CalcDate(Item."Lead Time Calculation", Today()) - Today()` and output as integer number of days.

### 3.8 Pricing
- Standard Microsoft Shopify Connector price calculation is completely untouched. Zero custom pricing overrides.

---

## 4. Current Production Implementation

The extension is implemented across 7 AL source files under `src/`:

1. **[`AddItemImageGate.ReportExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/AddItemImageGate.ReportExt.al)** (`ReportExtension 90300`): Intercepts `Report 30106` `OnBeforePreDataItem()`. Evaluates `IsItemApproved` AND `Picture.Count() > 0` AND master data fields (`GetCustomerItemReference`, `GetBrandName`, `BaseUnitOfMeasure`).
2. **[`ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al)** (`Codeunit 90302`): Event subscribers for `OnAfterProductsToSynchronizeFiltersSet`, `OnAfterInsertEvent` (Table 30127), and `OnBeforeUpdateProductMetafields`.
3. **[`ShopifyReadinessMgt.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyReadinessMgt.Codeunit.al)** (`Codeunit 90301`): Calculates readiness status on Item records evaluating `APSS Approved`, `Picture`, `GetCustomerItemReference`, `Brand`, and `Base Unit of Measure`.
4. **[`ShopifyProductTitle.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyProductTitle.Codeunit.al)** (`Codeunit 90300`): Dynamic `RecordRef`/`FieldRef` helpers for `APSS Approved` (Field 50001) and `APSS Brand` field, plus title formatting (`[Brand] - [Vendor Item No.] - [Description]`) and `GetCustomerItemReference`.
5. **[`ItemShopifyReady.TableExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemShopifyReady.TableExt.al)** (`TableExtension 90300`): Custom readiness fields on Item table (`APSS Has Shopify Image`, `APSS Shopify Ready`, `APSS Shopify Validation`).
6. **[`ItemListShopify.PageExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemListShopify.PageExt.al)** (`PageExtension 90300`): Readiness fields and refresh actions on Item List page.
7. **[`ShopifyEnhancements.PermissionSet.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyEnhancements.PermissionSet.al)** (`PermissionSet 90300`): Permission set for custom extension objects.

---

## 5. Architecture & Execution Flow

### Add Items Flow (New Products)
```
BC Item
  └─► Report 30106 "Shpfy Add Item to Shopify"
        └─► OnBeforePreDataItem()
              ├─► Evaluate IsItemApproved(Item) AND Picture.Count() > 0 AND GetCustomerItemReference(Item) <> '' AND Master Data
              └─► Apply Filter ("No." = Valid Item List OR 'APSS_NO_IMAGE_MATCH')
                    └─► Standard Shopify Product Creation
```

### Existing Product Sync Flow
```
Shopify Products Synchronization
  └─► Codeunit 30178 "Shpfy Sync Products"
        └─► OnAfterProductsToSynchronizeFiltersSet
              ├─► Evaluate IsItemApproved(Item) AND Picture.Count() > 0
              └─► Filter ShopifyProduct."Item SystemId"
                    └─► Standard Shopify Product Update
```

### Metafields Population Flow
```
Shpfy Product Event (Insert / Before Metafield Update)
  └─► AutoPopulateProductMetafields / OnAfterInsertShopifyProduct
        └─► PopulateProductMetafieldRecords()
              ├─► custom.brand = GetBrandName(Item)
              ├─► custom.manufacture_number = GetCustomerItemReference(Item)
              ├─► custom.uom = Item."Base Unit of Measure"
              ├─► custom.incoterms = 'EXW'
              └─► custom.lead_time = Integer Days
                    └─► Shpfy Metafield (Table 30137)
                          └─► GraphQL metafieldsSet
```

---

## 6. Implementation by Source File

| File Path | Object Type & ID | Object Name | Primary Responsibility |
| :--- | :--- | :--- | :--- |
| [`src/AddItemImageGate.ReportExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/AddItemImageGate.ReportExt.al) | `ReportExtension 90300` | `APSS Add Item Image Gate` | Image & Approval Gate for Add Items report |
| [`src/ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al) | `Codeunit 90302` | `APSS Shopify Sync Events` | Sync filter subscribers & automatic 5-metafield sync |
| [`src/ShopifyReadinessMgt.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyReadinessMgt.Codeunit.al) | `Codeunit 90301` | `APSS Shopify Readiness Mgt.` | Calculates readiness status on Item records |
| [`src/ShopifyProductTitle.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyProductTitle.Codeunit.al) | `Codeunit 90300` | `APSS Shopify Product Title` | Product title formatting & GetCustomerItemReference helper |
| [`src/ItemShopifyReady.TableExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemShopifyReady.TableExt.al) | `TableExtension 90300` | `APSS Item Shopify Ready` | Custom readiness fields on Item table (90300..90302) |
| [`src/ItemListShopify.PageExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemListShopify.PageExt.al) | `PageExtension 90300` | `APSS Item List Shopify` | Readiness fields and refresh actions on Item List |
| [`src/ShopifyEnhancements.PermissionSet.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyEnhancements.PermissionSet.al) | `PermissionSet 90300` | `APSS SHOPIFY ENH` | Permission set for custom extension objects |

---

## 7. Test Environment & Test Data

- **Environment:** Business Central Sandbox `June9`
- **Shop Code:** `APSS SHOP`
- **Target Controlled Items:**
  - `APSS-TEST-BULK-005` (No image test item)
  - `APSS-TEST-BULK-004` (Image gate test item / Product `16162981249327`)
  - `APSS-TEST-META-001` (Metafield test item / Product `16162851422511`)
  - `APSS-TEST-UOM-002A` (UOM test item)
  - `APSSDANID0004` (Readiness test item)

---

## 8. HISTORICAL ORIGINAL PHASE 1 EVIDENCE

> [!NOTE]
> **Historical Evidence Notice:** The evidence below was recorded during the initial implementation of Phase 1 when `custom.manufacture_number` was mapped from `Item."Vendor Item No."` (`AB-998877`) and `custom.description` was synchronized as a 6th custom metafield. This evidence is preserved as historical verification proof of image gating, background log behavior, and original test runs, but does NOT represent the current Customer Item Reference mapping.

### Test 1: APSSDANID0004 / Log 64844
- Evaluated initial readiness check and image evaluation baseline on Item `APSSDANID0004` (Log `64844`).

### Test 2A: APSSDANID0004 Readiness Baseline
- Initial Item List readiness check correctly flagged missing image and master data fields on Item `APSSDANID0004`.

### Test 2B: Image Gate Negative Path (APSS-TEST-BULK-005)
- **Item:** `APSS-TEST-BULK-005` (`Picture.Count() = 0`)
- **Execution:** Ran `Report 30106` "Shpfy Add Item to Shopify".
- **Result:** Item filtered locally at `OnBeforePreDataItem()`. 0 products created in Shopify, 0 mapping records inserted, 0 GraphQL API calls made, 0 Shopify Log error entries.
- **Status:** **PASS (Historical)**

### Test 2C: Image Gate Positive Path (APSS-TEST-BULK-004)
- **Item:** `APSS-TEST-BULK-004` (`Picture.Count() > 0`)
- **Execution:** Ran `Report 30106` "Shpfy Add Item to Shopify".
- **Result:** Item passed image gate; created Shopify Product `16162981249327` and valid BC ↔ Shopify mapping record. Log entries `64854`, `64855`, `64856`.
- **Status:** **PASS (Historical)**

### Test 3A: Historical Metafields Sync (APSS-TEST-META-001)
- **Item:** `APSS-TEST-META-001`
- **Historical Log Entry:** `64918`
- **Historical Metafield Results:**
  - `custom.manufacture_number` = `AB-998877` *(from Vendor Item No. in historical code)*
  - `custom.description` = `Item.Description` *(custom metafield present in historical code)*
  - `custom.brand` = `ALLEN-BRADLEY`
  - `custom.uom` = `EA`
  - `custom.incoterms` = `EXW`
  - `custom.lead_time` = `10`
- **Status:** **HISTORICAL (Superseded by Customer Reference mapping & custom.description removal)**

### Test 4: Existing Product Sync Image Gate (APSS-TEST-BULK-004)
- **Target Product:** `16162981249327`
- **Execution:** Removed BC picture for `APSS-TEST-BULK-004` and ran Products Synchronization.
- **Result:** Product excluded by `FilterProductsWithoutImageOnSync`; 0 update GraphQL calls executed.
- **Status:** **PASS (Historical)**

### Test UOM-002: Logs 66473, 66474
- Verified `custom.uom = BOX` mapping and 10x quantity scaling behavior.

### Test UOM-002A: Logs 66482, 66483
- Verified `custom.uom = EA` mapping and 6 metafield population in historical test run.

---

## 9. CURRENT UPDATED PHASE 1 EVIDENCE

> [!IMPORTANT]
> **Current Runtime Verification:** The evidence below was recorded during the final controlled runtime validation of the **CURRENT codebase** after updating `custom.manufacture_number` to Customer Item Reference No. (`REF-CUST-99001`) and removing `custom.description` from custom metafield code.

- **Environment:** Business Central Sandbox `June9` (`APSS SHOP`)
- **Target Item:** `APSS-TEST-META-001`
- **Target Shopify Product ID:** `16162851422511`
- **Target Customer Reference No.:** `REF-CUST-99001` (`Reference Type = Customer`)
- **Master Data Verification:**
  - `APSS Approved` = `TRUE`
  - `Picture.Count() > 0` (`Present`)
  - `Base Unit of Measure` = `'EA'`
  - `APSS Brand` = `'ALLEN-BRADLEY'`
  - `Lead Time Calculation` = `10D`
- **Current Runtime Results:**
  - `custom.manufacture_number` = `REF-CUST-99001` (from Customer Item Reference)
  - `custom.brand` = `ALLEN-BRADLEY`
  - `custom.uom` = `EA`
  - `custom.incoterms` = `'EXW'`
  - `custom.lead_time` = `10`
  - `custom.description` = **NOT WRITTEN BY CUSTOM CODE** (Native description handled by Standard Connector)
  - GraphQL `userErrors` = `[]` (Empty)
  - Target product `16162851422511` touched **ONLY** (0 other products modified).
- **Test Isolation & Cleanup:** A temporary single-item isolation filter (`SetRange(Id, 16162851422511L)`) was added strictly for this test, removed immediately after, and the production extension rebuilt cleanly with **0 errors, 0 warnings**.
- **Status:** **PASS (Current)**

---

## 10. UOM Investigation

### Proven Findings
1. **Quantity/Price Scaling Effect:** The controlled UOM comparison demonstrated a 10× quantity/price scaling effect consistent with the configured `BOX = 10 EA` conversion. This confirms the UOM scaling behavior observed in the test; it does not introduce or modify custom UOM conversion logic.
2. **Metafield Mapping:** `custom.uom` maps `Item."Base Unit of Measure"` directly (`EA` or `BOX`). No custom UOM unit conversion logic is implemented in Phase 1.

### Unproven Findings & Pricing Notes
1. **Observed Price Transformation:** In test runs, a BC Unit Price of `$150.00` yielded a Shopify variant price of `$193.08` (multiplier `1.2872`). The exact tenant database settings causing this price transformation (such as Shop Card pricing settings, VAT posting groups, tax area codes, currency exchange rates, or Customer Price Groups) were not directly inspected.
2. **Standard Pricing Intact:** Standard Microsoft Shopify Connector pricing calculation logic remains completely untouched. Zero custom AL price overrides are implemented in Phase 1.

---

## 11. Regression / Evidence Matrix

### Category A: Historical Original Phase 1 Evidence (Labeled HISTORICAL)

| Test ID | Item / Product ID | Operation | Expected Historical Result | Verified Runtime Result | Log IDs | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TEST 2B** | `APSS-TEST-BULK-005` | Add Items report | `Picture.Count() = 0` item filtered at `OnBeforePreDataItem()`. | 0 products created, 0 mappings inserted. | None (Local filter) | **PASS (Historical)** |
| **TEST 2C** | `APSS-TEST-BULK-004` / `16162981249327` | Add Items report | Item with picture creates Shopify product. | Product `16162981249327` created and mapped. | `64854`, `64855`, `64856` | **PASS (Historical)** |
| **TEST 3A** | `APSS-TEST-META-001` | Metafield trigger | 6 metafields written (`manufacture_number` = `AB-998877`). | Historical 6 metafields written. | `64918` | **HISTORICAL (Superseded)** |
| **TEST 4** | `APSS-TEST-BULK-004` / `16162981249327` | Sync Products | Image removed; product excluded from sync. | Product update skipped. | None (Local filter) | **PASS (Historical)** |
| **UOM-002** | `APSS-TEST-UOM-002` | Metafield trigger | `custom.uom = BOX` populated. | `custom.uom = BOX` written. | `66473`, `66474` | **PASS (Historical)** |
| **UOM-002A** | `APSS-TEST-UOM-002A` | Metafield trigger | `custom.uom = EA` populated. | `custom.uom = EA` written. | `66482`, `66483` | **PASS (Historical)** |

### Category B: Current Updated Phase 1 Evidence (Labeled CURRENT)

| Test ID | Item / Product ID | Customer Reference No. | Expected Current Result | Verified Runtime Result | GraphQL userErrors | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CURRENT E2E** | `APSS-TEST-META-001` / `16162851422511` | `REF-CUST-99001` | 5 Metafields updated (`manufacture_number` = `REF-CUST-99001`); `custom.description` NOT written | 5 Metafields written, `custom.description` omitted, target product only | `[]` (Empty) | **PASS (Current)** |

---

## 12. Known Limitations & Open Business Questions

1. **Multiple Customer Reference Selection Rule:** Table 5777 `Item Reference` permits multiple records per Item for different Customer Nos (`Reference Type No.`), Variant Codes, or Date Ranges. When multiple Customer References exist, current technical implementation retrieves the first matching record via `FindFirst()`. `FindFirst()` is a technical fallback behavior, **NOT** a confirmed final business selection rule. Establishing a deterministic Customer No. filter or selection rule for multi-Customer items remains an open business clarification for Kathy/Lead.
2. **Connector Single-Item Sync Limitation:** Standard Microsoft Shopify Connector does not provide single-item sync request page filters, requiring temporary code hooks for isolated single-item testing.
3. **No AL Test Runner:** Automated unit tests are not present in the repository. Clean compilation validation is maintained via `alc.exe`.

---

## 13. Phase 2 Deferred Scope

The following items are genuinely deferred to Phase 2:
- `custom.price_valid_until` (Deactivated in Phase 1)
- Datasheet / Product Specs attachments mechanism
- Custom UOM fallback / unit conversion logic
- Custom price override engine

> [!NOTE]
> `Reference Number` is **NOT** listed in Phase 2 because Customer Item Reference `Reference No.` is already implemented in Phase 1 for `custom.manufacture_number`.

---

> [!NOTE]
> **Controlled E2E vs. Production Readiness:** The controlled E2E confirms the tested current implementation. Production readiness remains CONDITIONAL because the business selection rule for Items with multiple Customer References is still pending confirmation.

---

## 14. Final Status Summary

| Item | Status |
| :--- | :--- |
| **Implementation** | **PASS** |
| **Code Review** | **PASS** |
| **Automated Unit Tests** | **NOT AVAILABLE** |
| **Current Controlled E2E** | **PASS** (Item `APSS-TEST-META-001` / Product `16162851422511` / `REF-CUST-99001`) |
| **Multi-Customer Reference Selection** | **Pending Business Clarification** |
| **Build** | **PASS** (`0` errors, `0` warnings with `alc.exe`) |
| **Cleanup** | **PASS** |
| **Documentation** | **PASS** |
| **Production Ready** | **CONDITIONAL** (Implementation and AL build complete; multi-Customer Reference selection rule pending business confirmation) |
