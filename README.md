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

## Production & Deployment Warning

- Do not publish directly to production.
- Test thoroughly in the BC 28 Sandbox environment.
- Export the `.app` package and review code before promoting to Production.

