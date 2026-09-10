# APSS Shopify Enhancements

Per-tenant extension for Business Central and Microsoft Shopify Connector integration.

---

## Runtime Test Results

### TEST 1 — Shopify Product Metafield Auto-Population

Verifies the automatic product metafield population flow during product synchronization.

- **Test Item**: `APSSDANID0004`
- **Shop**: `APSS SHOP`
- **Configuration**: Standard product sync with automatic metafield event handler active.
- **Expected Behavior**: Metafields (`custom.incoterms`, `custom.uom`, `custom.description`) automatically construct and write to Shopify without requiring manual definition actions.
- **Actual Result**: Metafields were successfully written to Shopify with `userErrors = []`.
- **PASS/FAIL**: **PASS**
- **Runtime & API Log Evidence**:
  - **Shopify GraphQL Log 64844**: `metafieldsSet` mutation executed successfully.
  - **Populated Fields**:
    - `custom.incoterms`
    - `custom.uom`
    - `custom.description`
  - **Shopify Response**: `userErrors = []`
  - **Other Evidence**: Metafield values successfully verified in Shopify. No manual "Get Metafield Definitions" action was required for the tested item.

---

### TEST 2 — Shopify Product Image Readiness / Image Gate

#### Test 2A — Readiness Validation

Verifies the Shopify readiness validation rules on item records.

- **Test Item**: `APSSDANID0004`
- **Expected Behavior**: Accurately detect missing or invalid fields and set readiness status accordingly.
- **Actual Result**:
  - `Has Shopify Image` = `Yes` (BC Picture present)
  - `Shopify Ready` = `No` (Item correctly remained not ready)
  - `Validation Detected`:
    - Missing product number
    - Missing or invalid unit price
  - `APSS Brand` runtime value = `ALLEN-BRADLEY`
- **PASS/FAIL**: **PASS** (PASS for the tested readiness/validation rules; item correctly remained not ready because required fields were missing/invalid).

---

#### Test 2B — No Image Item Is Skipped

Verifies that items without a BC picture are intercepted and excluded before reaching Shopify product creation.

- **Test Item**: `APSS-TEST-BULK-005` (`Picture.Count() = 0`, `Blocked = No`, `Approved Item = Yes`)
- **Add Items Configuration**:
  - `Shop Code` = `APSS SHOP`
  - `Sync Images` = OFF
  - `Sync Inventory` = OFF
  - `No.` = `APSS-TEST-BULK-005`
  - `Blocked` = `No`
  - `Approved Item` = `Yes`
- **Expected Behavior**: The image gate prevents no-image items from running `ShopifyCreateProduct.Run(Item)` and creating products on Shopify.
- **Actual Result**:
  - Report 30106 ("Shpfy Add Item to Shopify") executed via **Product → Add Items → OK**.
  - Operation completed/closed without creating a Shopify product.
  - `APSS-TEST-BULK-005` was NOT created as a Shopify product in Shopify Admin.
  - No BC Shopify Product mapping was created.
  - No `productCreate` GraphQL log was generated.
  - No Shopify error was observed.
- **PASS/FAIL**: **PASS**
- **Runtime Evidence**: Explicit absence of any `productCreate` GraphQL log confirmed that the image gate successfully stopped the item prior to API invocation.

---

#### Test 2C — Image Item Is Successfully Added

Verifies that items with a BC picture are successfully processed and added to Shopify via Add Items.

- **Test Item**: `APSS-TEST-BULK-004` (`Picture` = Yes)
- **Add Items Configuration**:
  - `Shop Code` = `APSS SHOP`
  - `Sync Images` = ON
  - `Sync Inventory` = OFF
  - `Blocked` = `No`
  - `Approved Item` = `Yes`
- **Expected Behavior**: Item with image passes the report extension gate, creates BC Shopify Product mapping, and publishes product to Shopify Admin.
- **Actual Result**:
  - Item was successfully added to Shopify.
  - Product was created and visible in BC Shopify Products mapping.
  - Product was created and visible in Shopify Admin.
- **PASS/FAIL**: **PASS**
- **Creation Evidence (Log Numbers)**:
  - **Log 64854**: `productCreate`
  - **Log 64855**: `productVariantsBulkCreate`
  - **Log 64856**: `publishablePublish`
  *(Note: Log numbers 64854, 64855, 64856 are creation evidence specifically from the successful creation test run for APSS-TEST-BULK-004).*
