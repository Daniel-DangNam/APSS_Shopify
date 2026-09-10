# APSS Shopify Enhancements

Per-tenant extension (PTE) for Microsoft Dynamics 365 Business Central (BC 28) and Microsoft Shopify Connector integration, delivering enhanced product image filtering, automated product metafield synchronization, and Shopify readiness validation.

---

## Purpose

This extension extends standard Business Central and Microsoft Shopify Connector capabilities to ensure high-quality product publishing and automated metadata synchronization between Business Central and Shopify Admin.

It enforces image-presence rules before products are published or updated, calculates readiness status on Item records, and automatically maps and synchronizes custom product metafields.

---

## Implemented Features

- **Add Items Image Gate**: Prevents Shopify product creation for BC Items without pictures (`Picture.Count() = 0`).
- **Sync Products Image Gate**: Prevents existing Shopify products from being synchronized or updated when the linked BC Item has no picture.
- **Shopify Readiness Validation**: Calculates and displays readiness status (`APSS Has Shopify Image`, `APSS Shopify Ready`, `APSS Shopify Validation`) on Item records.
- **Automatic Metafield Population**: Automatically populates and updates six product metafields for both newly created products (**Add Items**) and existing products (**Sync Products**).
- **APSS Brand Resolution**: Dynamically reads `APSS Brand` field data from BC Items for titles and metafields.
- **Incoterms Default**: Automatically populates `custom.incoterms` with `EXW`.
- **Lead Time Integer Conversion**: Converts Business Central `Lead Time Calculation` (`DateFormula`, e.g. `10D`) into an integer day count (`10`) matching Shopify's `number_integer` metafield definition.
- **Phase 2 / Placeholders**:
  - Datasheet / Product Specs: Phase 2 (connector file upload limitation).
  - Price Valid Until: Left blank (no exact source field specified).
  - Reference Number: Left blank / not required.

---

## Implementation

### Image Gate — Add Items

- **File**: [`src/AddItemImageGate.ReportExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/AddItemImageGate.ReportExt.al)
- **Mechanism**: ReportExtension `90300 "APSS Add Item Image Gate"` extending Report `30106 "Shpfy Add Item to Shopify"`.
- **Logic**: Intercepts dataitem `Item` at `OnBeforePreDataItem()`, evaluates candidate items where `Item.Picture.Count() > 0`, and pre-filters `Item."No."` before the standard report reaches `ShopifyCreateProduct.Run(Item)`. If 0 items have pictures, a guaranteed no-match filter (`APSS_NO_IMAGE_MATCH`) is applied.

### Image Gate — Existing Product Sync

- **File**: [`src/ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al)
- **Event**: `[EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnAfterProductsToSynchronizeFiltersSet', '', false, false)]`
- **Logic**:
  1. Copies candidate filters applied to `ShopifyProduct` (`Record "Shpfy Product"`).
  2. Resolves linked BC Items via `Item.GetBySystemId(ShopifyProduct."Item SystemId")`.
  3. Evaluates `Item.Picture.Count() > 0`.
  4. Applies a filtered list of valid `Item SystemId` values to `ShopifyProduct`.
  5. If 0 products have pictures, applies `ShopifyProduct.SetRange("Item SystemId", CreateGuid())` (guaranteed no-match GUID filter).
  6. Excluded products are never returned by `ShopifyProduct.FindSet()`, preventing `UpdateProductData` from executing.

### Readiness / Validation

- **Files**:
  - [`src/ShopifyReadinessMgt.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyReadinessMgt.Codeunit.al)
  - [`src/ItemShopifyReady.TableExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemShopifyReady.TableExt.al)
  - [`src/ItemListShopify.PageExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemListShopify.PageExt.al)
- **User-Visible Fields**:
  - `APSS Has Shopify Image`: Boolean indicator whether `Item.Picture.Count() > 0`.
  - `APSS Shopify Ready`: Boolean status indicator.
  - `APSS Shopify Validation`: Text summary of validation findings (e.g. missing image, brand, part number, description, unit price, or blocked status).

### Automatic Metafields

- **File**: [`src/ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al)
- **New Products Flow**:
  `BC Item` → `Shopify Products` → `Add Items` → `Shopify productCreate` → `Shpfy Product OnAfterInsertEvent` → `APSS metafield population` → `metafieldsSet` → `Shopify Product Metafields`
- **Existing Products Flow**:
  `Shpfy Product Export` → `OnBeforeUpdateProductMetafields` → `APSS metafield population` → `metafieldsSet` → `Shopify Product Metafields`
- **Mechanism**: Writes/updates local BC Table 30137 `"Shpfy Metafield"` records and invokes `Codeunit 30418 "Shpfy Metafields".SyncMetafieldsToShopify(...)` to send GraphQL `metafieldsSet` to Shopify.

### Metafield Mapping

| Shopify Metafield | BC Source | Type | Logic / Behavior |
| --- | --- | --- | --- |
| `custom.brand` | `APSS Brand` | `single_line_text_field` | Dynamic `RecordRef` lookup for `APSS Brand*` fields. |
| `custom.manufacture_number` | `Vendor Item No.` | `single_line_text_field` | `Item."Vendor Item No."` |
| `custom.description` | `Item Description` | `single_line_text_field` | `Item.Description` |
| `custom.uom` | `Base Unit of Measure` | `single_line_text_field` | `Item."Base Unit of Measure"` |
| `custom.incoterms` | Fixed Default | `single_line_text_field` | Hardcoded `EXW` |
| `custom.lead_time` | `Lead Time Calculation` | `number_integer` | Converted `DateFormula` (e.g. `10D` → `10`) |

---

## How to Test

### Test 1 — Existing Product Metafield Population
- **Test Item**: `APSSDANID0004`
- **Shop**: `APSS SHOP`
- **Procedure**:
  1. Open Business Central → **Shopify Products** -> Actions -> **Synchronization** -> **Products**.
  2. Inspect **Shopify Log Entries** for `metafieldsSet` mutation.
  3. Verify `userErrors = []`.
  4. Verify metafields in Shopify Admin (`custom.incoterms`, `custom.uom`, `custom.description`).

### Test 2A — Readiness Validation
- **Test Item**: `APSSDANID0004`
- **Procedure**:
  1. Verify item has BC Picture (`Picture.Count() > 0`).
  2. Run **Refresh Selected Shopify Readiness** on Item List.
  3. Verify: `Has Shopify Image = Yes`, `Shopify Ready = No`.
  4. Verify validation message highlights missing product number and missing/invalid unit price.
  5. Verify `APSS Brand` evaluates to `ALLEN-BRADLEY`.

### Test 2B — No Image Item Blocked During Add Items
- **Test Item**: `APSS-TEST-BULK-005` (`Picture.Count() = 0`, `Blocked = No`, `Approved Item = Yes`)
- **Flow**: Business Central → **Shopify Products** → **Add Items**
- **Settings**: `Shop Code = APSS SHOP`, `Sync Images = OFF`, `Sync Inventory = OFF`, `No. = APSS-TEST-BULK-005`
- **Expected Behavior**: The image gate prevents no-image items from running `ShopifyCreateProduct.Run(Item)`.
- **Verification**: No Shopify Admin product created, no BC mapping created, no `productCreate` GraphQL log generated.

### Test 2C — Image Item Successfully Added
- **Test Item**: `APSS-TEST-BULK-004` (`Picture` = Yes, `Blocked` = No, `Approved Item` = Yes)
- **Flow**: Business Central → **Shopify Products** → **Add Items**
- **Settings**: `Shop Code = APSS SHOP`, `Sync Images = ON`, `Sync Inventory = OFF`
- **Verification**: Shopify Product created, BC mapping created, product visible in Shopify Admin.
- **Evidence**: Log 64854 (`productCreate`), Log 64855 (`productVariantsBulkCreate`), Log 64856 (`publishablePublish`). *(Note: Logs 64854-64856 are creation evidence from the initial creation run).*

### Test 3A — Automatic Product Metafield Population
- **Test Item**: `APSS-TEST-META-001`
  - Setup: Description = `Metafield Test Product`, APSS Brand = `ALLEN-BRADLEY`, Vendor Item No. = `AB-998877`, Lead Time Calculation = `10D`, Base Unit of Measure = `EA`, Unit Price = `150.00`, Blocked = No, Approved = Yes, Picture = Yes.
- **Flow**: Business Central → **Shopify Products** → **Add Items**
- **Settings**: `Shop Code = APSS SHOP`, `No. = APSS-TEST-META-001`, `Sync Images = ON`, `Sync Inventory = OFF`
- **Runtime Evidence**:
  - Shopify Log Entry `64918` (`metafieldsSet`, `userErrors = []`).
  - Shopify Admin verified: UOM = `EA`, INCOTERMS = `EXW`, Lead Time = `10`, Manufacture Number = `AB-998877`, Brand = `ALLEN-BRADLEY`, Description = `Metafield Test Product`.
- **Lead Time Behavior**: BC stores `10D` as `DateFormula`. Implementation converts `10D` to integer `10` matching Shopify's `number_integer` definition.
- **Diagnostic History**: Log `64908` was an intermediate run where `lead_time` was sent as `single_line_text_field` while Shopify defined it as `number_integer`. Fixed by sending `Enum::"Shpfy Metafield Type"::number_integer` and integer days. Log `64918` is the final passing evidence.

### Test 4 — Existing Product Synchronization (No-Image Gate)
- **Target Shopify Product ID**: `16162981249327`
- **BC Item**: `APSS-TEST-BULK-004` (BC Picture removed while existing BC ↔ Shopify mapping remained active).
- **Shop**: `APSS SHOP`
- **Flow**: Business Central → **Shopify Products** → Actions → **Synchronization** → **Products**
- **Controlled Test Isolation vs Production Logic**:
  - During controlled runtime verification, a TEMPORARY test filter targeting Product ID `16162981249327` and diagnostic `Message()` calls were added to trace execution.
  - Diagnostics confirmed: Product `16162981249327` resolved, `Item.Picture.Count() = 0`, `ValidProductCount = 0`, final no-match `Item SystemId` filter applied, and `ShopifyProduct.FindSet()` returned `false`.
  - The target product had no matching synchronization record remaining after the APSS image gate, so standard product update processing (`UpdateProductData`) was not invoked for the target.
  - Zero GraphQL update calls (`productUpdate`, `productVariantsBulkCreate`, `metafieldsSet`) were generated for the target product.
  - The temporary test filter and diagnostic messages were completely removed after verification, leaving the production image gate subscriber intact.

---

## Runtime Test Results

### TEST 1 — Shopify Product Metafield Auto-Population
- **Test Item**: `APSSDANID0004`
- **Shop**: `APSS SHOP`
- **Expected Behavior**: Metafields (`custom.incoterms`, `custom.uom`, `custom.description`) automatically construct and write to Shopify.
- **Actual Result**: Metafields written successfully with `userErrors = []`.
- **PASS/FAIL**: **PASS**
- **Log Evidence**: Shopify GraphQL Log `64844` (`metafieldsSet`).

### TEST 2A — Readiness Validation
- **Test Item**: `APSSDANID0004`
- **Actual Result**: `Has Shopify Image = Yes`, `Shopify Ready = No`. Validation correctly detected missing product number and invalid unit price. APSS Brand = `ALLEN-BRADLEY`.
- **PASS/FAIL**: **PASS**

### TEST 2B — No Image Item Blocked
- **Test Item**: `APSS-TEST-BULK-005` (`Picture.Count() = 0`)
- **Actual Result**: Add Items completed without creating a Shopify product. No BC mapping, no `productCreate` log.
- **PASS/FAIL**: **PASS**

### TEST 2C — Image Item Added
- **Test Item**: `APSS-TEST-BULK-004` (`Picture` = Yes)
- **Actual Result**: Product created in Shopify Admin and BC mapping created.
- **PASS/FAIL**: **PASS**
- **Log Evidence**: Logs `64854`, `64855`, `64856`.

### TEST 3A — Automatic Product Metafield Population
- **Test Item**: `APSS-TEST-META-001`
- **Actual Result**: All 6 metafields automatically created and populated in Shopify Admin upon product creation.
- **PASS/FAIL**: **PASS**
- **Log Evidence**: Shopify GraphQL Log `64918` (`metafieldsSet`, `userErrors = []`).

### TEST 4 — Existing Product Sync No-Image Gate
- **Test Item**: `APSS-TEST-BULK-004` (Picture removed) / Product ID `16162981249327`
- **Actual Result**: Product excluded by image gate prior to API invocation. Zero GraphQL update calls generated.
- **PASS/FAIL**: **PASS**

---

## Phase 2 / Known Limitations

- **Datasheet / Product Specs**: Phase 2 (connector file upload limitation).
- **Price Valid Until**: Blank (no exact BC source field identified).
- **Reference Number**: Blank / not required.
- **UOM Fallback / Quantity-Price Conversion**: **NOT COMPLETED / OPEN ITEM**.
  - *Note*: The UOM fallback runtime test was not completed because the sandbox environment encountered Business Central Dimension / Item Tracking setup conflicts during test item configuration.

---

## Test Summary

| Test | Scenario | Result |
| --- | --- | --- |
| **1** | Existing product metafield population | **PASS** |
| **2A** | Shopify readiness / validation | **PASS** |
| **2B** | No-image item blocked during Add Items | **PASS** |
| **2C** | Image item successfully added | **PASS** |
| **3A** | Automatic 6-metafield population | **PASS** |
| **4** | Existing no-image product excluded from Sync Products | **PASS** |
| **UOM** | EA fallback / quantity-price conversion | **NOT COMPLETED** |
