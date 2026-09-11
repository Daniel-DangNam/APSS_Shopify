# APSS Shopify Enhancements

Per-tenant extension (PTE) for Microsoft Dynamics 365 Business Central (BC 28) and Microsoft Shopify Connector integration, delivering enhanced product image filtering, automated product metafield synchronization, and Shopify readiness validation.

---

## 1. Project Objective

The primary objective of the **APSS Shopify Enhancements** extension is to extend standard Microsoft Dynamics 365 Business Central and Microsoft Shopify Connector capabilities to ensure high-quality product publishing and automated metadata synchronization between Business Central and Shopify Admin.

Specifically, the extension:
- Enforces strict image-presence gates before Business Central items can be published as new products or updated as existing products in Shopify.
- Calculates and presents real-time Shopify readiness status on Business Central Item records.
- Automatically populates and synchronizes six core custom product metafields to Shopify Admin.
- Preserves Business Central master data integrity without modifying standard pricing logic or unit of measure setups.

---

## 2. Phase 1 Scope

All Phase 1 functional requirements in the agreed scope are verified and PASS.

### Phase 1 Functional Scope Items:
1. **Add Items Image Gate**: Prevents Shopify product creation for BC Items without pictures (`Picture.Count() = 0`).
2. **Existing Product Sync Image Gate**: Excludes existing Shopify products from synchronization or update cycles when the linked BC Item has no picture (`Picture.Count() = 0`).
3. **Shopify Readiness Validation**: Calculates, evaluates, and displays real-time readiness status (`APSS Has Shopify Image`, `APSS Shopify Ready`, `APSS Shopify Validation`) on Item records and Item List pages.
4. **Automatic 6-Metafield Population**: Automatically populates and updates six custom product metafields during both initial creation (**Add Items**) and subsequent synchronization (**Sync Products**):
   - `custom.brand`
   - `custom.manufacture_number`
   - `custom.description`
   - `custom.uom`
   - `custom.incoterms`
   - `custom.lead_time`
5. **APSS Brand Resolution**: Dynamically resolves the `APSS Brand` field value from Business Central Items for use in titles and metafields.
6. **Incoterms Default**: Automatically populates `custom.incoterms` with the hardcoded default `EXW`.
7. **Lead Time Integer Conversion**: Converts Business Central `Lead Time Calculation` (`DateFormula`, e.g. `10D`) into an integer day count (`10`) matching Shopify's `number_integer` metafield definition.
8. **UOM Mapping from Base UOM**: Maps `custom.uom` directly from Business Central `Item."Base Unit of Measure"`.

---

## 3. Explicit Phase 1 Exclusions / Phase 2 Scope

The following items are explicitly excluded from Phase 1 and deferred to Phase 2 or pending business confirmation:

- `custom.price_valid_until`: Deferred to Phase 2. (Kathy clarified that if applicable price records exist, the nearest/recently updated one should be considered, and an Ending Date in the past is not automatically invalid. No selection algorithm or source has been implemented in Phase 1.)
- **Datasheet / Product Specs**: Deferred to Phase 2 due to standard Connector file upload limitations.
- **Reference Number**: Deferred to Phase 2 pending business source specification. (Vendor Item No. is NOT assumed as the required reference source.)
- **UOM Fallback Conversion / Price Overrides**: Any UOM fallback price calculation or master data modification is excluded from Phase 1 per Lead instructions. Business Central `Sales Unit of Measure` remains untouched.

---

## 4. Architecture / Event Flow

### Add Items Image Gate Flow
`BC Item` $\rightarrow$ `Report 30106 "Shpfy Add Item to Shopify"` $\rightarrow$ `OnBeforePreDataItem()` $\rightarrow$ Filter items where `Picture.Count() > 0` $\rightarrow$ `ShopifyCreateProduct.Run(Item)` (No-image items never reach product creation).

### Sync Products Image Gate Flow
`Shopify Products Sync` $\rightarrow$ `Codeunit 30174 "Shpfy Sync Products"` $\rightarrow$ `OnAfterProductsToSynchronizeFiltersSet` $\rightarrow$ Filter `ShopifyProduct` by `Item SystemId` where `Picture.Count() > 0` $\rightarrow$ `UpdateProductData` (No-image products are excluded prior to GraphQL update calls).

### Automatic Metafields Population Flow (New Products)
`BC Item` $\rightarrow$ `Shopify Add Items` $\rightarrow$ `productCreate` $\rightarrow$ `Shpfy Product OnAfterInsertEvent` subscriber $\rightarrow$ `PopulateProductMetafieldRecords` $\rightarrow$ `SyncMetafieldsToShopify` $\rightarrow$ GraphQL `metafieldsSet` $\rightarrow$ Shopify Product Metafields.

### Automatic Metafields Population Flow (Existing Products)
`Shopify Products Sync` $\rightarrow$ `OnBeforeUpdateProductMetafields` subscriber $\rightarrow$ `PopulateProductMetafieldRecords` $\rightarrow$ `SyncMetafieldsToShopify` $\rightarrow$ GraphQL `metafieldsSet` $\rightarrow$ Shopify Product Metafields.

---

## 5. Implementation Summary by Source File

All extension objects use assigned ID range `90300` to `90349`:

1. **[`src/AddItemImageGate.ReportExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/AddItemImageGate.ReportExt.al)** (ReportExtension `90300 "APSS Add Item Image Gate"`):
   - Extends Report `30106 "Shpfy Add Item to Shopify"`.
   - Intercepts `Item` dataitem at `OnBeforePreDataItem()`, evaluates candidate items where `Picture.Count() > 0`, and applies a filtered list of valid `Item."No."` values. If zero candidate items have pictures, applies guaranteed no-match filter `'APSS_NO_IMAGE_MATCH'`.

2. **[`src/ShopifySyncEvents.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifySyncEvents.Codeunit.al)** (Codeunit `90302 "APSS Shopify Sync Events"`):
   - `FilterProductsWithoutImageOnSync`: Event subscriber to `OnAfterProductsToSynchronizeFiltersSet`. Filters `ShopifyProduct` records to include only items with `Picture.Count() > 0`.
   - `OnAfterInsertShopifyProduct`: Subscriber to `Shpfy Product` table `OnAfterInsertEvent`. Validates `Rec.IsTemporary()`, `Rec.Id <> 0`, `Rec."Item SystemId"`, and `Rec."Shop Code"`, populates local metafield records, and invokes `SyncMetafieldsToShopify`.
   - `AutoPopulateProductMetafields`: Subscriber to `OnBeforeUpdateProductMetafields` event for existing product updates.
   - `PopulateProductMetafieldRecords`: Central helper constructing all 6 metafield records.
   - `SetOrUpdateMetafield`: Manages insert/modify operations on Table 30137 `"Shpfy Metafield"`.

3. **[`src/ShopifyReadinessMgt.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyReadinessMgt.Codeunit.al)** (Codeunit `90301 "APSS Shopify Readiness Mgt."`):
   - Evaluates item image presence (`Picture.Count() > 0`), brand, product number, description, unit price (`> 0`), and blocked status. Updates persisted readiness fields (`APSS Has Shopify Image`, `APSS Shopify Ready`, `APSS Shopify Validation`) on Item records. Provides batch and single-record refresh procedures (`RefreshItem`, `RefreshAllItems`, `RefreshSelectedItems`).

4. **[`src/ShopifyProductTitle.Codeunit.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyProductTitle.Codeunit.al)** (Codeunit `90300 "APSS Shopify Product Title"`):
   - Formats product titles using pattern `[Brand] - [Vendor Item No.] - [Description]`.
   - `GetBrandName`: Performs dynamic `RecordRef` / `Field` virtual table lookup for `APSS Brand` field data.
   - `GetProductNumber`: Resolves product part number from `Item."Vendor Item No."`.

5. **[`src/ItemShopifyReady.TableExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemShopifyReady.TableExt.al)** (TableExtension `90300 "APSS Item Shopify Ready"`):
   - Extends Table `27 "Item"` with three custom fields: `APSS Has Shopify Image` (Boolean), `APSS Shopify Ready` (Boolean), and `APSS Shopify Validation` (Text[250]).

6. **[`src/ItemListShopify.PageExt.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ItemListShopify.PageExt.al)** (PageExtension `90300 "APSS Item List Shopify"`):
   - Extends Page `31 "Item List"`. Adds readiness fields to the grid and exposes actions `Refresh Selected Shopify Readiness` and `Refresh All Shopify Readiness`.

7. **[`src/ShopifyEnhancements.PermissionSet.al`](file:///d:/APSS%20Training/APSS/APSS_Shopify/src/ShopifyEnhancements.PermissionSet.al)** (PermissionSet `90300 "APSS SHOPIFY ENH"`):
   - Grants required permissions for custom codeunits, table extensions (`Item` read/modify), `Shpfy Product` read, and `Shpfy Metafield` read/insert/modify/delete.

8. **[`app.json`](file:///d:/APSS%20Training/APSS/APSS_Shopify/app.json)**:
   - Configures extension metadata, target `Cloud`, runtime `17.0`, platform/application `28.0.0.0`, ID range `90300-90349`, and dependency on Microsoft Shopify Connector (`ec255f57-31d0-4ca2-b751-f2fa7c745abb`).

---

## 6. Test Environment

- **Business Central Version**: Microsoft Dynamics 365 Business Central 2026 Release Wave 1 (BC 28.0).
- **Shopify Connector Version**: Microsoft Shopify Connector `28.0.0.0`.
- **Target Shopify Store / Shop Code**: `APSS SHOP`.
- **Compiler**: Microsoft (R) AL Compiler version `17.0.34.45391`.

---

## 7. Test Data

| Item No. | Description | Base UOM | Sales UOM | Qty/UOM | Unit Price | Vendor Item No. | Brand | Picture | Status / Usage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `APSSDANID0004` | Existing Product Test | `EA` | `EA` | 1 | 150.00 | `AB-1234` | `ALLEN-BRADLEY` | Yes | Existing product sync & readiness test |
| `APSS-TEST-BULK-005` | Bulk Test Negative | `EA` | `EA` | 1 | 100.00 | `BULK-005` | `ALLEN-BRADLEY` | No | Add Items negative gate test |
| `APSS-TEST-BULK-004` | Bulk Test Positive | `EA` | `EA` | 1 | 120.00 | `BULK-004` | `ALLEN-BRADLEY` | Yes / Removed | Add Items positive & sync gate test |
| `APSS-TEST-META-001` | Metafield Test Product | `EA` | `EA` | 1 | 150.00 | `AB-998877` | `ALLEN-BRADLEY` | Yes | 6-Metafield population verification |
| `APSS-TEST-UOM-002` | UOM Base Unit Test | `EA` | `BOX` | 10 | 150.00 | `UOM-002` | `ALLEN-BRADLEY` | Yes | UOM-002 Base vs Sales UOM test |
| `APSS-TEST-UOM-002A` | TEST-UOM-002A | `EA` | `EA` | 1 | 150.00 | `UOM-002A` | `ALLEN-BRADLEY` | Yes | UOM-002A Base=Sales UOM test |

---

## 8. Detailed Phase 1 Test Procedures

### Test 1 — Existing Product Metafield Population
- **Item**: `APSSDANID0004` | **Shop**: `APSS SHOP`
- **Procedure**: Open Business Central $\rightarrow$ **Shopify Products** $\rightarrow$ Actions $\rightarrow$ **Synchronization** $\rightarrow$ **Products**. Inspect **Shopify Log Entries** for `metafieldsSet` mutation. Verify `userErrors = []` and inspect metafield values in Shopify Admin.

### Test 2A — Readiness Validation
- **Item**: `APSSDANID0004`
- **Procedure**: Verify item picture presence (`Picture.Count() > 0`). Run **Refresh Selected Shopify Readiness** on Item List. Verify grid fields `APSS Has Shopify Image = Yes`, `APSS Shopify Ready = No`, and verify validation message summary.

### Test 2B — No Image Item Blocked During Add Items
- **Item**: `APSS-TEST-BULK-005` (`Picture.Count() = 0`, `Blocked = No`, `Approved Item = Yes`)
- **Procedure**: Navigate to Business Central $\rightarrow$ **Shopify Products** $\rightarrow$ **Add Items**. Set `Shop Code = APSS SHOP`, `No. = APSS-TEST-BULK-005`, `Sync Images = OFF`, `Sync Inventory = OFF`. Run report.
- **Expected Outcome**: Gate intercepts item prior to `ShopifyCreateProduct.Run(Item)`. Zero Shopify products created, zero BC mappings inserted, zero `productCreate` API calls generated.

### Test 2C — Image Item Successfully Added
- **Item**: `APSS-TEST-BULK-004` (`Picture` = Yes, `Blocked` = No, `Approved Item` = Yes)
- **Procedure**: Navigate to Business Central $\rightarrow$ **Shopify Products** $\rightarrow$ **Add Items**. Set `Shop Code = APSS SHOP`, `Sync Images = ON`, `Sync Inventory = OFF`. Run report.
- **Expected Outcome**: Shopify Product created, BC mapping inserted, GraphQL creation calls logged.

### Test 3A — Automatic Product Metafield Population
- **Item**: `APSS-TEST-META-001`
- **Procedure**: Run **Add Items** report for `APSS-TEST-META-001`. Inspect Shopify Log Entries and Shopify Admin product metafields.
- **Expected Outcome**: All 6 metafields automatically written with `userErrors = []`.

### Test 4 — Existing Product Synchronization (No-Image Gate)
- **Target Product ID**: `16162981249327` | **BC Item**: `APSS-TEST-BULK-004` (Picture removed while BC ↔ Shopify mapping remained active).
- **Procedure**: Execute **Synchronization** $\rightarrow$ **Products**.
- **Expected Outcome**: Product filtered by `FilterProductsWithoutImageOnSync` (`ValidProductCount = 0`). Standard `UpdateProductData` skipped. Zero GraphQL update calls generated.

### UOM-002 — Base UOM vs Sales UOM
- **Item**: `APSS-TEST-UOM-002` (`Base UOM = EA`, `Sales UOM = BOX`, `BOX = 10 EA`, Unit Price = `150.00`)
- **Procedure**: Run **Add Items** for `APSS-TEST-UOM-002`. Inspect Shopify Log Entries and Admin Metafields.
- **Expected Outcome**: `custom.uom = EA` written to metafield. Standard Connector uses `Sales Unit of Measure = BOX` for price calculation.

### UOM-002A — Base UOM = Sales UOM (EA)
- **Item**: `APSS-TEST-UOM-002A` (`Base UOM = EA`, `Sales UOM = EA`, `EA = 1`, Unit Price = `150.00`)
- **Procedure**: Run **Add Items** for `APSS-TEST-UOM-002A`. Inspect Shopify Log Entries and Admin Metafields.
- **Expected Outcome**: `custom.uom = EA` written to metafield. Product and variant created.

---

## 9. Runtime Evidence

### Test 1 Evidence
- **Item**: `APSSDANID0004`
- **Shopify Log Entry**: `64844` (`metafieldsSet`, `userErrors = []`).
- **Verified Values**: Metafields written successfully to Shopify Admin.

### Test 2A Evidence
- **Item**: `APSSDANID0004`
- **Readiness Status**: `APSS Has Shopify Image = Yes`, `APSS Shopify Ready = No`. Validation message correctly identified missing product number and invalid unit price. Brand resolved as `ALLEN-BRADLEY`.

### Test 2B Evidence
- **Item**: `APSS-TEST-BULK-005`
- **Execution Result**: Add Items report executed cleanly. Gate applied `'APSS_NO_IMAGE_MATCH'`.
- **Runtime Metrics**: 0 products created in Shopify, 0 BC mapping records inserted, 0 `productCreate` API calls generated.

### Test 2C Evidence
- **Item**: `APSS-TEST-BULK-004`
- **Shopify Product ID**: `16162981249327`
- **Shopify Log Entries**: Log `64854` (`productCreate`), Log `64855` (`productVariantsBulkCreate`), Log `64856` (`publishablePublish`).

### Test 3A Evidence
- **Item**: `APSS-TEST-META-001`
- **Shopify Log Entry**: `64918` (`metafieldsSet`, `userErrors = []`).
- **Verified Admin Metafields**:
  - `custom.brand` = `ALLEN-BRADLEY`
  - `custom.manufacture_number` = `AB-998877`
  - `custom.description` = `Metafield Test Product`
  - `custom.uom` = `EA`
  - `custom.incoterms` = `EXW`
  - `custom.lead_time` = `10` (integer day count converted from `10D`)

### Test 4 Evidence
- **Item**: `APSS-TEST-BULK-004` (Picture removed for test) / Shopify Product ID `16162981249327`
- **Execution Result**: `FilterProductsWithoutImageOnSync` resolved product, evaluated `Item.Picture.Count() = 0`, set `ValidProductCount = 0`, and applied guaranteed no-match GUID filter `ShopifyProduct.SetRange("Item SystemId", CreateGuid())`.
- **Runtime Metrics**: `ShopifyProduct.FindSet()` returned `false`. Zero GraphQL update calls (`productUpdate`, `productVariantsBulkCreate`, `metafieldsSet`) generated.

### UOM-002 Evidence
- **Item**: `APSS-TEST-UOM-002`
- **Shopify Log Entry 66473** (`metafieldsSet`, `userErrors = []`): `custom.uom = EA`, `custom.brand = ALLEN-BRADLEY`, `custom.manufacture_number = UOM-002`, `custom.description = UOM Base Unit Test`, `custom.incoterms = EXW`, `custom.lead_time = 10`.
- **Shopify Log Entry 66474** (`productVariantsBulkCreate`, `userErrors = []`): Sent variant price = `1930.77`.
- **Confirmed Standard Behavior**: Standard Microsoft Shopify Connector explicitly passes `Item."Sales Unit of Measure"` (`BOX`) into `Codeunit 30182 "Shpfy Product Price Calc."`.

### UOM-002A Evidence
- **Item**: `APSS-TEST-UOM-002A`
- **Shopify Log Entry 66482** (`metafieldsSet`, `userErrors = []`): `custom.brand = ALLEN-BRADLEY`, `custom.manufacture_number = UOM-002A`, `custom.description = TEST-UOM-002A`, `custom.uom = EA`, `custom.incoterms = EXW`, `custom.lead_time = 10`.
- **Shopify Log Entry 66483** (`productVariantsBulkCreate`, `userErrors = []`): SKU = `APSS-TEST-UOM-002A`, sent variant price = `193.08`.

---

## 10. UOM Investigation and Business Constraints

### Proven Findings & UOM Isolation Analysis
1. **UOM Scaling Isolation**:
   - `UOM-002` (`Sales UOM = BOX`, 10 EA) produced Shopify variant price `1930.77`.
   - `UOM-002A` (`Sales UOM = EA`, 1 EA) produced Shopify variant price `193.08`.
   - Ratio: $\frac{1930.77}{193.08} \approx 10.00$, matching `BOX = 10 EA`.
   - The $10\times$ UOM quantity scaling isolation between UOM-002 and UOM-002A is **PROVEN**.
2. **UOM-002A Verified Successes**:
   - Product and variant creation: **PASS**.
   - `custom.uom = EA` mapping: **PASS**.
   - All 6 Metafields population: **PASS**.
3. **Price Discrepancy & Multiplier Analysis**:
   - BC Item Card Unit Price = `150.00`.
   - Shopify Variant Price sent = `193.08`.
   - Observed Multiplier = `1.2872`.
   - The same approximate multiplier ($1.2872$) was observed in UOM-002 after accounting for the $10\times$ UOM factor ($\frac{1930.77}{1500.00} = 1.28718$).
   - **Exact Source Status**: The exact source of the $1.2872$ multiplier remains **UNPROVEN** because the runtime Business Central tenant database configuration (such as Shop Card pricing settings, VAT posting groups, tax area codes, currency exchange rates, or Customer Price Groups) was not directly inspected.
   - Specific tenant configuration items are **NOT** claimed as confirmed sources without direct database configuration evidence.
   - The $150.00 \rightarrow 193.08$ price transformation is **NOT** claimed as a business-requirement PASS.
4. **Business Central Master Data & Code Constraints**:
   - Business Central master data remains unchanged (`Sales Unit of Measure` is NOT modified to match `Base Unit of Measure`).
   - No custom AL price override was implemented because standard Microsoft Shopify Connector price calculation must remain untouched per Lead instructions.

---

## 11. Final Regression Matrix

All Phase 1 functional requirements in the agreed scope are verified and PASS.

| Test ID | Item | Exact Operation | Expected Result | Actual Result | Shopify Log Entry IDs | GraphQL userErrors | Shopify Admin Result | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TEST A (Image Gate Negative)** | `APSS-TEST-BULK-005` | Add Items report execution | `Picture.Count() = 0` item filtered at `OnBeforePreDataItem()`; product NOT created. | 0 products created, 0 mapping records inserted, 0 API calls. | None (Gated locally) | `[]` | No product created | **PASS** |
| **TEST B (Image Positive Path)** | `APSS-TEST-BULK-004` | Add Items report execution | Item with picture passes gate, creates BC ↔ Shopify mapping without duplicates. | Product created (`16162981249327`), mapping valid. | `64854`, `64855`, `64856` | `[]` | Product created & active | **PASS** |
| **TEST C (Automatic Metafields)** | `APSS-TEST-META-001` / `APSS-TEST-UOM-002A` | Product creation metafield trigger | Populates 6 metafields (`brand`, `manufacture_number`, `description`, `uom`, `incoterms`, `lead_time`). | All 6 metafields populated automatically. | `64918` / `66482` | `[]` | 6 Metafields written | **PASS** |
| **TEST D (UOM Mapping)** | `APSS-TEST-UOM-002A` | Product creation metafield trigger | `custom.uom` maps `Item."Base Unit of Measure"` (`EA`). | `custom.uom = EA` populated on Shopify Admin. | `66482` | `[]` | `custom.uom = EA` | **PASS** |
| **TEST E (Readiness Validation)** | `APSSDANID0004` | Item List `Refresh Selected Readiness` | Evaluates readiness (`Has Image = Yes`, `Ready = No`, validation summary updated). | Fields updated on Item Card, Brand resolved (`ALLEN-BRADLEY`). | N/A (BC local action) | N/A | Readiness fields updated | **PASS** |
| **TEST F (Existing Sync Image Gate)** | `APSS-TEST-BULK-004` (`16162981249327`) | Products Synchronization | Excludes existing mapped product when BC Picture is removed. | Product excluded by `FilterProductsWithoutImageOnSync`; 0 update calls. | None (Gated locally) | `[]` | Product update skipped | **PASS** |

---

## 12. Known Limitations / Open Business Confirmations

1. **UOM Price Scaling Alignment**: Standard Microsoft Shopify Connector natively computes product prices using `Item."Sales Unit of Measure"`, whereas `custom.uom` is mapped from `Item."Base Unit of Measure"`. Business confirmation from Kathy remains pending regarding whether Shopify always sells using Base UOM or supports Sales UOM fallbacks.
2. **Observed Price Multiplier**: In the test environment, BC Unit Price `150.00` yields Shopify variant price `193.08` (multiplier `1.2872`). The exact tenant pricing configuration causing this multiplier remains unproven without direct database setup inspection. Standard Connector price calculation remains untouched.
3. **Phase 2 Scope Exclusions**: `custom.price_valid_until`, Datasheet/Product Specs, and Reference Number are excluded from Phase 1.

---

## 13. Final Phase 1 Status

### **PASS / READY FOR LEAD SIGN-OFF**

All Phase 1 functional requirements in the agreed scope are verified and PASS. No Phase 1 implementation defects were identified during the source audit. The implementation is compile-clean and has passed the documented runtime regression tests.

---

## 14. Phase 2 Backlog

- **`custom.price_valid_until`**: Implement nearest/recently updated price selection logic once business algorithm is finalized by Kathy.
- **Datasheet / Product Specs**: Implement product specification document attachment mechanism once Shopify API / Connector file upload capabilities are established.
- **Reference Number**: Implement reference number mapping once the authoritative business source field (e.g. Manufacturer Part No. or Vendor Item No.) is confirmed.
- **UOM Business Fallback**: Implement custom UOM fallback/conversion logic if Kathy confirms a mandatory requirement to override standard Connector pricing behavior for multi-UOM items.
