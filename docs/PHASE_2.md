# Phase 2: Implementation & E2E Validation

## 1. Architectural Changes

- **Pricing Integration**: Confirmed **OPTION A** (Event Subscriber). Integrated with the standard BC Pricing Engine (`Codeunit 7020 "Sales Line - Price"`) via `OnAfterSetPrice`. This captures the exact `PriceListLine."Ending Date"` during the pricing calculation of the active variant/item.
- **State Management**: Created a `SingleInstance` dictionary in `ShopifySyncEvents` to cache the `Ending Date` from `OnAfterSetPrice`. The cache is cleared precisely in `OnAfterProductsToSynchronizeFiltersSet` to prevent cross-job pollution.
- **Metafield Population**: Extended `OnBeforeUpdateProductMetafields` to fetch the cached `Ending Date` and push to `custom.price_valid_until` (Date format).
- **Stale Metafield Removal**: When no valid ending date exists, the implementation prepares the `price_valid_until` metafield for clearing during synchronization. The actual Shopify-side clearing behavior remains subject to runtime E2E validation.
- **Pricing Cache Key**: The cached Ending Date is keyed by Item No. because `price_valid_until` is represented at the Shopify product level rather than at the individual variant level.

## 2. Blocked / Deferred Items

- **Datasheet / Product Specs**: The hosting strategy and public URL generation mechanism for Business Central document attachments have not been finalized or implemented in the current scope.
- **Send Inquiry**: Send Inquiry is handled by the current Shopify storefront/theme behavior. No custom AL backend implementation was added in this scope.

## 3. E2E Runtime Validation Status

- **UOM**: PASS – Runtime evidence available from Phase 1.
- **Datasheet**: DEFERRED – No implementation or runtime test.
- **Pricing**: Pending runtime environment (T-P2-01 through T-P2-05, T-P2-07 defined below).
- **Test Scenarios defined for when environment is restored**:
  1. **T-P2-01**: Sync Item with Sales Price & valid Ending Date -> `price_valid_until` set on Shopify.
  2. **T-P2-02**: Sync Item with no Ending Date -> `price_valid_until` is cleared on Shopify.
  3. **T-P2-03**: Sync Item with 0.00 Price -> Sync succeeds, price is 0.00 (triggers Send Inquiry on storefront).
  4. **T-P2-04**: Sync Item with multiple variants -> Base product `price_valid_until` is correctly populated.
  5. **T-P2-07**: Phase 1 Regression (Manufacture No, UOM, Approval Gate, Incoterms, Picture req) remains functioning.

## 4. Current Status

The implemented Phase 2 code has compiled successfully. UOM runtime validation is complete. Pricing E2E validation remains pending, and Datasheet/Product Specs is deferred from the current scope.

---

## 5. UOM Mapping Runtime Verification

### Business Rules & Scope

- `custom.uom` on Shopify is strictly mapped from Business Central `Item."Base Unit of Measure"`.
- `Item."Sales Unit of Measure"` is not used for mapping `custom.uom` and remains unchanged in Business Central.
- No UOM unit conversion, fallback, or scaling logic is implemented.
- Datasheet / Product Specs is out of scope for the current UOM verification.

### Runtime Verification Summary

| Test Case | Item No. | Base UOM | Sales UOM | Expected `custom.uom` | Actual `custom.uom` | Result |
|---|---|---|---|---|---|---|
| Base UOM = Sales UOM | `APSS-TEST-UOM-002A` | EA | EA | EA | EA | PASS |
| Base UOM != Sales UOM | `APSS-TEST-UOM-002` | EA | BOX | EA | EA | PASS |

### Test Case A Evidence (Base UOM = Sales UOM)

- **Item No.**: `APSS-TEST-UOM-002A`
- **Master Data**: `Base Unit of Measure` = `EA`, `Sales Unit of Measure` = `EA`, `APSS Approved` = `Yes`, Picture = Present, Brand = `ALLEN-BRADLEY`, Customer Reference = `UOM-002A`.
- **Shopify Log Entry 66482 (`metafieldsSet`)**:
  - `custom.uom` = `EA`
  - `custom.incoterms` = `EXW`
  - `custom.lead_time` = `10`
  - `custom.description` = `TEST-UOM-002A`
  - `custom.manufacture_number` = `UOM-002A`
  - `custom.brand` = `ALLEN-BRADLEY`
  - `userErrors` = `[]`
- **Shopify Log Entry 66483 (`productVariantsBulkCreate`)**:
  - SKU: `APSS-TEST-UOM-002A`, Price: `193.08`, Variant created successfully, `userErrors` = `[]`
- **Status**: **PASS**

### Test Case B Evidence (Base UOM ≠ Sales UOM)

- **Item No.**: `APSS-TEST-UOM-002`
- **Master Data**: `Base Unit of Measure` = `EA`, `Sales Unit of Measure` = `BOX` (`BOX` Qty. per UOM = 10), `APSS Approved` = `Yes`, Picture = Present, Brand = `ALLEN-BRADLEY`, Customer Reference = `UOM-002`.
- **Shopify Log Entry 66473 (`metafieldsSet`)**:
  - `custom.uom` = `EA`
  - `custom.incoterms` = `EXW`
  - `custom.lead_time` = `10`
  - `custom.description` = `UOM Base Unit Test`
  - `custom.manufacture_number` = `UOM-002`
  - `custom.brand` = `ALLEN-BRADLEY`
  - `userErrors` = `[]`
- **Shopify Log Entry 66474 (`productVariantsBulkCreate`)**:
  - SKU: `APSS-TEST-UOM-002`, Price: `193.77`, Variant created successfully, `userErrors` = `[]`
- **Status**: **PASS**

### Key Findings & Verification

- Both GraphQL `metafieldsSet` requests executed with `userErrors = []`.
- Both items created Shopify product variants successfully.
- `custom.uom` received `EA` in both test cases, matching `Item."Base Unit of Measure"`.
- For `APSS-TEST-UOM-002`, `Item."Sales Unit of Measure"` remained `BOX` in Business Central without alteration.
- No UOM conversion or fallback logic was introduced or executed.
- Confirms that the current extension implementation strictly maps `custom.uom` from `Item."Base Unit of Measure"`.

---

## 6. Datasheet / Product Specs – Deferred

### Current Status

* **Status:** **DEFERRED / OUT OF CURRENT SCOPE**
* **Reason:** Requires hosting strategy for Business Central binary document attachments and decision on Shopify Files API / public URL generation, which are not implemented in the current scope.

### Business Requirements (Confirmed by Kathy)

- **Expected Data Source:** Business Central **Item Document Attachment** (`Table 1173 Document Attachment`).
- **Supported File Formats:** **PDF, PNG, JPG**.
- **File Selection & Priority Rules:**
  - If PDF files exist, prioritize PDF files.
  - If multiple PDF files exist, select the PDF file with the most recent `Last Modified Date Time`.
  - If no PDF file exists, evaluate eligible PNG/JPG files and select the file with the most recent `Last Modified Date Time`.
- **Shopify Target Mapping:** Intended to map to **Shopify Product Specs – the metafield key and metafield type have not been confirmed.**

### Open Questions & Pending Confirmations

- > [!IMPORTANT]
  > **`[PENDING CONFIRMATION / OPEN QUESTION]`** Business rule for when an Item has **NO Datasheet attachment** (e.g. clear existing metafield, omit from GraphQL payload, or set to null).
- > [!IMPORTANT]
  > **`[PENDING CONFIRMATION / OPEN QUESTION]`** Business rule for when a Datasheet attachment is **updated or deleted** in Business Central (e.g. trigger automatic deletion of Shopify file/metafield or soft-unlink).

### Technical Analysis & Unconfirmed Decisions (Tech Lead)

- **Source Location:** Item Document Attachment confirmed as source.
- **Hosting & Public URL Strategy:** **Unconfirmed.** Business Central document attachments are stored as internal BLOBs requiring authentication. A mechanism to generate an unauthenticated public URL accessible by storefront customers (e.g., Azure Blob Storage, CDN, or Shopify Files API) has not been selected.
- **File Upload Location:** **Unconfirmed.** Decision pending between uploading files to Shopify Files via GraphQL `stagedUploadsCreate` / `fileCreate` vs hosting externally on public cloud storage.
- **Shopify Metafield Type:** **Unconfirmed.** Pending choice between `file_reference`, `url`, or `single_line_text_field`.

### Unimplemented Scope

- **AL Source Code:** No AL implementation has been added specifically for Datasheet/Product Specs in the current codebase.
- **Runtime Testing:** No Datasheet runtime tests executed.
- **Shopify E2E Evidence:** No GraphQL logs for file upload or Product Specs metafield synchronization.

### Prerequisites for Future Implementation

1. Tech Lead & Business confirmation of Phase scope.
2. Finalized decision on Shopify Metafield Type.
3. Finalized hosting & public URL strategy (Shopify Files API vs Azure/CDN).
4. Approved business rules for `no-file`, `file update`, and `file delete` scenarios.


