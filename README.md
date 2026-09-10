## APSS Shopify Enhancements

Per-tenant extension for Business Central (BC 28) and Microsoft Shopify Connector integration.

## Summary of Features & Implementation

### 1. Title Formatting (`ShopifyProductTitle.Codeunit.al`)
- Builds Shopify product titles dynamically as: `Brand - Product Number - Description`.
- Brand is derived from `Item."Manufacturer Code"`.
- Product Number is derived from `Item."Vendor Item No."`.
- Reused by both product synchronization and readiness validation logic.

### 2. Readiness Checks & Image-Gate Guard (`ShopifySyncEvents.Codeunit.al`, `ItemCard.PageExt.al`, `ItemList.PageExt.al`)
- Added fields to `Item`:
  - `Has Shopify Image` (Boolean)
  - `Shopify Ready` (Boolean)
  - `Shopify Validation` (Text)
- Provides actions on Item List / Item Card to refresh Shopify readiness status.
- **Image-Gate (Safety Guard)**:
  - Subscribes to `OnBeforeCreateShopifyProductVariant` and `OnBeforeUpdateShopifyProductVariant`.
  - When an Item has no picture (`Item.Picture.Count = 0`), sets `Title := ''` to safely instruct the Shopify Connector to skip the item without deleting temporary variant records (preventing the `"The Shopify Variant table is empty"` runtime error).

### 3. Product Metafield Automation (`ShopifySyncEvents.Codeunit.al`)
- Subscribes to `OnBeforeUpdateProductMetafields(ProductId)` to construct and push product metafields to Shopify during product sync.

### 4. Configuration & Launch Fixes (`.vscode/launch.json`)
- Corrected `startupObjectId` in `launch.json` to `31` (Item List) to ensure smooth Web Client debugging (F5).

---

## Setup & Publishing

1. Open `app.json` and confirm platform, application, runtime, ID range, and Shopify Connector dependency versions match your Business Central environment.
2. Open `.vscode/launch.json` and configure `environmentName` and `environmentType` (Sandbox).
3. Run **AL: Download Symbols** (`Ctrl+Shift+P` -> `AL: Download Symbols`).
4. Compile with `Ctrl+Shift+B`.
5. Publish to Sandbox with `F5`.

---

## Sandbox Testing Guide

1. **Readiness Check**:
   - Select an Item with `Manufacturer Code`, `Vendor Item No.`, `Description`, `Unit Price`, and an Item Picture.
   - Run **Refresh Selected Shopify Readiness**.
   - Confirm `Has Shopify Image` and `Shopify Ready` are `Yes`.

2. **Image Guard Test**:
   - Try synchronizing an Item without an image.
   - Verify that the Connector skips the product safely without throwing `"The Shopify Variant table is empty"`.

3. **Product Sync**:
   - Set the Shopify Shop's created-product status to `Draft`.
   - Run **Sync Products** to Shopify and verify the resulting product title format (`Brand - Part No - Description`) and metafields.

---

## Runtime Test Results

### Test 1 — Controlled Shopify Product Synchronization

- **Status**: **PASS (single-product controlled runtime test: PASS)**

#### Test Environment & Prerequisites
- **BC Sandbox**: June9
- **Shopify Shop**: APSS SHOP
- **BC Item**: APSSDANID0004
- **Item Description**: 440G-LZS21UPRH
- **Shopify Product ID**: 16142496104751
- **Shopify Product GID**: `gid://shopify/Product/16142496104751`
- **Shopify Variant ID**: 58382185464111 *(Note: 58382185464111 is a Shopify ProductVariant ID belonging to Product 16142496104751, NOT a different product)*
- **Item State**: BC Picture present (`Picture.Count > 0`), Blocked = No, Item Approved = Yes, Base UOM = EA, Inventory Posting Group = RESALE, VAT Prod. Posting Group = OUT_OF_SCOPE.
- **Posting Setup**: Shop VAT Bus. Posting Group = GST_REGISTERED, VAT Posting Setup combination (`GST_REGISTERED` + `OUT_OF_SCOPE`) exists. APSS-AU location has valid Inventory Posting Setup for `RESALE`.
- **Existing Mapping**: Shopify Product 16142496104751 exists on Shopify and is mapped to APSSDANID0004.

#### Controlled Sync Execution & Results
- **Test Harness**: A temporary test filter (`ShopifyProduct.SetFilter(Id, '16142496104751')`) was applied to subscriber `OnAfterProductsToSynchronizeFiltersSet` in `ShopifySyncEvents.Codeunit.al` to restrict `Shpfy Product Export` specifically to this single product. *(Note: This filter was a test-only harness and is NOT production functionality).*
- **Sync Result**:
  - The controlled export executed successfully for Product `16142496104751`.
  - No unrelated Shopify Product IDs were processed in the test logs during this controlled run.
  - Shopify metafield mutation succeeded without errors (`"userErrors": []`).
  - Metafields returned by Shopify: `custom.incoterms`, `custom.uom`, `custom.description`.
  - No Shopify API user errors were returned for this mutation.

#### Important Clarifications & Notes
- **Single-Product Controlled Test vs. UI Limitation**:
  - `single-product controlled runtime test`: **PASS**
  - Standard Shopify Connector UI Limitation: Page filters applied on the Shopify Products page (Page 30126) do not restrict Report 30108 ("Shpfy Sync Products"). The controlled single-product test was achieved via the event subscriber harness.
- **Inventory Account Notifications**:
  - Inventory Account notifications/warnings observed during general testing belong to known sandbox setup issues on unrelated unconfigured items. They do not constitute a Test 1 failure for Product `16142496104751`.

---

## Production & Deployment Warning

- Do not publish directly to production.
- Test thoroughly in the BC 28 Sandbox environment.
- Export the `.app` package and review code before promoting to Production.


