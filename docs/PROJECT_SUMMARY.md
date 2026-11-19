# APSS Shopify Enhancements — Complete Technical & Operational Summary (Go-Live Baseline v1.0.0.29)

> **Status:** Production Live
> **Extension Name:** `APSS Shopify Enhancements` (`APSS`)
> **App ID:** `6bc2d1a6-7ceb-4f94-a665-a12c753d284b`
> **Version:** `1.0.0.29` (AL Runtime `17.0`, Target `Cloud`, `NoImplicitWith`)
> **Platform / Application:** Microsoft Dynamics 365 Business Central `28.0.0.0`
> **Dependency:** Microsoft `Shopify Connector` (`ec255f57-31d0-4ca2-b751-f2fa7c745abb`, `v28.0.0.0`)
> **Object ID Range:** `90300` – `90349`

This document is the single authoritative technical reference for the **APSS Shopify Enhancements** Per-Tenant Extension (PTE). It consolidates all phases (Phase 1, Phase 2, Phase 3, Auto Sync Job Queue, HTML/GraphQL Sanitization, and Fault-Tolerant Batching) into one complete guide for future maintenance, debugging, and feature upgrades.

---

## 1. High-Level Architecture & End-to-End Flow

The extension hooks into Business Central and the Microsoft Shopify Connector via **Event Subscribers**, a **Report Extension**, **Custom Staging/Log Tables**, **Admin/User UIs**, and a **Fault-Tolerant Background Job Queue**.

```text
Trigger:
  ├── [Automated] Job Queue Entry -> Codeunit 90306 ("APSS Shopify Auto Sync Job")
  └── [Manual UI] Item List -> Action "Add Ready Items to Shopify" (PageExt 90300 -> Page 90300)
          │
          ▼
1. Readiness Evaluation (Codeunit 90301 "APSS Shopify Readiness Mgt.")
   ├── Sanitize Marketing Text (Codeunit 90304.SanitizeItemMarketingText)
   ├── Validate 5 Gates: APSS Approved, Picture > 0, Brand <> '', Description <> '', Base UOM <> ''
   ├── Check Unresolved Reconcile Log (Table 90301)
   └── Classify: New Ready | Modified Ready | Synced Unchanged | Needs Reconciliation | Not Ready
          │
          ▼
2. 4-Branch SKU Precheck (Codeunit 90304 "APSS Shopify SKU Precheck")
   ├── OAuth 24h Token Auto-Refresh via IsolatedStorage (Client Credentials)
   ├── GraphQL Check (POST /admin/api/2024-01/graphql.json)
   └── Decision: Create | Update | Block (SKU Collision / Stale Mapping / Payload Limit -> Table 90301)
          │
          ▼
3. Fault-Tolerant Batch Sync (Chunks of 100 items, wrapped in [TryFunction])
   ├── New Ready      -> Report 30106 ("Shpfy Add Item to Shopify", SyncInventory = true)
   │                     └─ ReportExt 90300 ("APSS Add Item Image Gate") enforces gates
   ├── Modified Ready -> Report 30108 ("Shpfy Sync Products", targeted SystemId filter)
   └── Images         -> Report 30107 ("Shpfy Sync Images")
          │
          ▼
4. Connector Event Hooks (Codeunit 90302 & Codeunit 90300)
   ├── OnAfterFillInShopifyProductFields -> Title (CU 90300) + SEO Title/Desc (CU 90302)
   ├── OnBeforeCalculateUnitPrice        -> Temp Sales Quote (Qty = 1.0) -> Staging Table 90306
   ├── OnAfterCreateProductBodyHtml / OnBeforeSendCreate|Update -> CleanMarketingHtmlForGraphQL
   └── OnAfterInsert / OnBeforeUpdateProductMetafields -> Populate & Sync Product + Variant Metafields
          │
          ▼
5. Reporting & Logging
   ├── APSS Shopify Email Mgt. (Codeunit 90303) -> HTML Summary Email (SYNCED vs FAILED)
   ├── APSS Diagnostic Log (Table 90305 / Page 90305) -> Execution & Pricing traces
   └── APSS Shpfy Reconcile Log (Table 90301 / Page 90303) -> Blocked items for bulk resolution
```

---

## 2. Complete Object & File Inventory (24 Files in 9 Folders)

### 2.1 `src/Codeunit/` (Business Logic & Event Subscribers)

| File | Object ID & Name | Key Responsibilities |
| :--- | :--- | :--- |
| `ShopifyProductTitle.Codeunit.al` | `Codeunit 90300`<br>`APSS Shopify Product Title` | • Subscribes to `OnAfterFillInShopifyProductFields` to set `ShopifyProduct.Title` = `Brand + ' ' + Description` with anti-duplication.<br>• Dynamic `FieldRef` lookup for `APSS Brand` (fallback `Brand Code` / `Brand`) and `APSS Approved` (fallback `Approved` / `APSS Shopify Approved`).<br>• Helper `GetCustomerItemReference` (`Item Reference` where `Type = Customer`). |
| `ShopifyReadinessMgt.Codeunit.al` | `Codeunit 90301`<br>`APSS Shopify Readiness Mgt.` | • `EvaluateItemReadiness`: Checks `APSS Approved`, `Picture.Count() > 0`, `Brand`, `Description`, `Base Unit of Measure`. Writes missing reasons to `APSS Shopify Validation`.<br>• `RefreshItem`: Calls `SanitizeItemMarketingText`, evaluates readiness, and calls `Item.Modify(false)` **only if readiness fields changed** (prevents false `SystemModifiedAt` bumps on synced items).<br>• `GetItemSyncStatus`: Evaluates `Not Ready` -> `Needs Reconciliation` -> `New Ready` -> `Modified Ready` (`Item.SystemModifiedAt > ShpfyProduct.SystemModifiedAt`) -> `Synced Unchanged`.<br>• `CalculateReadinessStatistics`: Aggregates counts for the FactBox. |
| `ShopifySyncEvents.Codeunit.al` | `Codeunit 90302`<br>`APSS Shopify Sync Events` | • `SingleInstance = true` (holds `SelectedModifiedItemFilter` and active price calculation state).<br>• `FilterProductsWithoutImageOnSync`: Purges `Table 90306` per shop, purges ghost `Shpfy Product` records (`Id = 0`), applies exclusion filters (`<>Guid1&<>Guid2...`) to avoid BC's filter complexity limit.<br>• `CalculateUnitPriceWithQuantityOne`: Forces `TempSalesLine.Validate(Quantity, 1)` inside `[TryFunction]` `TryCalculatePrice`, binding `Shpfy Update Price Source`. Captures `Ending Date` from both **New Pricing** (`CU 7020`) and **Legacy Pricing** (`CU 7000`) into `Table 90306`.<br>• Metafield sync (`OnAfterInsertEvent` on `Shpfy Product` & `OnBeforeUpdateProductMetafields`) for Product & Variant metafields.<br>• SEO population (`SEO Title <= 70`, `SEO Description <= 160` plain text) & HTML cleaning on `OnAfterCreateProductBodyHtml`, `OnBeforeSendCreateShopifyProduct`, `OnBeforeSendUpdateShopifyProduct`. |
| `APSSShopifyEmailMgt.Codeunit.al` | `Codeunit 90303`<br>`APSS Shopify Email Mgt.` | • Dispatches HTML emails via `Email Scenario::"APSS Shopify Procurement"` to `ShpfyShop."APSS Procurement Email"`.<br>• `SendSyncNotification`: Builds summary email with KPI cards (`New Items Created`, `Modified Items Updated`) and item-by-item breakdown (`SYNCED` green badge vs `FAILED` red badge with error details from `Table 90301` or `APSS Shopify Validation`, fallback `Not updated (Pending review)`).<br>• `SendSyncErrorNotification`: Red alert HTML template for fatal batch errors. |
| `APSSShopifySKUPrecheck.Codeunit.al` | `Codeunit 90304`<br>`APSS Shopify SKU Precheck` | • **OAuth & Secrets:** Stores `Client ID`, `Client Secret`, `Access Token`, and `Expiry` in `IsolatedStorage` (`DataScope::Module`). Auto-refreshes 24h tokens via `POST /admin/oauth/access_token` (`grant_type=client_credentials`).<br>• **4-Branch SKU Precheck (`EvaluateItemSyncEligibility`):** Evaluates `Create`, `Update`, `Block (SKU Collision)`, `Block (Stale Mapping)`, plus `CheckItemPayloadLimit` (checks `Marketing Text > 100,000` chars or `Description > 255`).<br>• **Marketing Text Sanitizer (`CleanMarketingHtmlForGraphQL` & `SanitizeItemMarketingText`):** Strips embedded `data:image` base64 payloads, converts tabbed specs (`\t`) into clean 2-column HTML `<table>`, escapes quotes (`"` -> `'`), removes raw `\r`/`\n`/`\t` to prevent GraphQL `400 Bad Request`.<br>• **Reconcile Resolution (`ApplyMappingsFromReconcileLog`):** Links existing Shopify Products/Variants back to BC Items and auto-populates `Vendor`, `Product Type`, `SEO`, `URL`, and timestamps. |
| `APSSShopifyAutoSyncJob.Codeunit.al` | `Codeunit 90306`<br>`APSS Shopify Auto Sync Job` | • `TableNo = "Job Queue Entry"`; reads `ShopCode` from `Rec."Parameter String"`.<br>• Refreshes all items quietly, collects `New Ready` and `Modified Ready`, runs SKU Precheck, and executes Reports `30106`, `30108`, and `30107`.<br>• **100-item Chunking:** Splits `New` and `Modified` batches into max 100 items per `Report.Execute` call to stay well below BC's ~2,000 filter token limit.<br>• **Fault-Tolerance:** Each chunk runs inside `[TryFunction]` (`TryExecuteAddItemReport`, `TryExecuteSyncProductsReport`, `TryExecuteSyncImagesReport`) with `Commit()` boundaries; chunk errors log to `Table 90305` and skip without putting the Job Queue into `Error` status.<br>• Sends 1 consolidated HTML email at the end of the run. |

### 2.2 `src/Table/` & `src/TableExt/` (Data Storage & Extensions)

| File | Object ID & Name | Key Fields & Purpose |
| :--- | :--- | :--- |
| `APSSShpfyItemSelBuffer.Table.al` | `Table 90300`<br>`APSS Shpfy Item Sel. Buffer` | Temporary buffer table (`TableType = Temporary`) backing `Page 90300` with `Selected` (Boolean), `Item No.`, `Description`, `Sync Status`. |
| `APSSShpfyReconcileLog.Table.al` | `Table 90301`<br>`APSS Shpfy Reconcile Log` | Persistent conflict log (`Entry No.`, `Logged At`, `Item No.`, `Variant Code`, `SKU`, `Shopify Product Id`, `Shopify Variant Id`, `Shopify Handle`, `Shopify Status`, `Reason`, `Details`, `Resolved`, `Selected`). Includes `LogReason` with deduplication on `(Item No., SKU, Reason, Resolved = false)`. |
| `APSSDiagnosticLog.Table.al` | `Table 90305`<br>`APSS Diagnostic Log` | Operational trace table (`Entry No.`, `Date Time`, `Session ID`, `Context`, `Item No.`, `Shop Code`, `Event Called`, `Calc Succeeded`, `Calculated Price`, `Captured Ending Date`, `Error Text`, `Details`). |
| `APSSItemPriceEndingDate.Table.al` | `Table 90306`<br>`APSS Item Price Ending Date` | Persistent staging table keyed by `("Item No.", "Shop Code")`. Stores `Ending Date`, `Has Variant Conflict`, `Last Updated`, `Last Session ID` to bridge NST session boundaries. |
| `ItemShopifyReady.TableExt.al` | `TableExtension 90300`<br>`APSS Item Shopify Ready` | Extends `Item`: `APSS Has Shopify Image` (`90300`), `APSS Shopify Ready` (`90301`), `APSS Shopify Validation` (`90302`, Text[250]). |
| `APSSShpfyShop.TableExt.al` | `TableExtension 90301`<br>`APSS Shpfy Shop` | Extends `Shpfy Shop`: `APSS Procurement Email` (`90300`), `APSS Shopify URL` (`90301`), `APSS Shopify Token` (`90302`, Masked), `APSS Enable SKU Precheck` (`90303`), `APSS Client ID` (`90304`), `APSS Client Secret` (`90305`, Masked). |

### 2.3 `src/Page/` & `src/PageExt/` (User Interface)

| File | Object ID & Name | Key Responsibilities |
| :--- | :--- | :--- |
| `ShopifyItemSelection.Page.al` | `Page 90300`<br>`APSS Shopify Item Selection` | Modal list page for manual sync selection (`Select All`, `Deselect All`, checkbox `Selected`). |
| `APSSShpfyReadinessFactBox.Page.al` | `Page 90302`<br>`APSS Shpfy Readiness FactBox` | `CardPart` FactBox on Item List showing `Total Items in BC`, `Total Eligible`, `New Ready`, `Modified Ready`, `Synced to Shopify`, `Not Ready`, plus `Refresh Statistics` action. |
| `APSSShpfyReconcileLog.Page.al` | `Page 90303`<br>`APSS Shpfy Reconcile Log` | Editable list page for conflict resolution with bulk actions: `Select All`, `Deselect All`, `Mark as Resolved`, `Mark ALL as Resolved`, `Delete Selected`, and `Apply Mapping to BC` (calls `ApplyMappingsFromReconcileLog`). |
| `APSSDiagnosticLogs.Page.al` | `Page 90305`<br>`APSS Diagnostic Logs` | Admin list page displaying `Table 90305` entries. |
| `ItemListShopify.PageExt.al` | `PageExtension 90300`<br>`APSS Item List Shopify` | Extends `Item List`: Adds readiness columns, `APSS Shopify Sync Status` with `StyleExpr`, `ShopifyReadinessFactBox`, and actions (`Refresh Selected`, `Refresh All`, `Add Ready Items to Shopify`, `Shopify Reconcile Log`). |
| `APSSShpfyShopCard.PageExt.al` | `PageExtension 90301`<br>`APSS Shpfy Shop Card` | Extends `Shpfy Shop Card`: Exposes setup fields (`90300..90305`) and `Test Shopify Precheck Connection` action. |

### 2.4 `src/Enum/`, `src/EnumExt/`, `src/ReportExt/`, `src/PermissionSet/`

| File | Object ID & Name | Purpose |
| :--- | :--- | :--- |
| `ShopifyItemSyncStatus.Enum.al` | `Enum 90300`<br>`APSS Shopify Item Sync Status` | `Not Ready` (0), `New Ready` (1), `Modified Ready` (2), `Synced Unchanged` (3), `Needs Reconciliation` (4). |
| `APSSShpfyReconcileReason.Enum.al` | `Enum 90301`<br>`APSS Shpfy Reconcile Reason` | `None` (0), `Missing Product on Shopify` (1), `SKU Already Exists on Shopify` (2), `Duplicate SKU in Batch` (3), `Payload Limit Exceeded` (4). |
| `APSSShpfySyncAction.Enum.al` | `Enum 90302`<br>`APSS Shpfy Sync Action` | `Skip` (0), `Create` (1), `Update` (2), `Block` (3). |
| `APSSEmailScenario.EnumExt.al` | `EnumExtension 90300`<br>`APSS Email Scenario` | Extends `Email Scenario` with `value(90300; "APSS Shopify Procurement")`. |
| `AddItemImageGate.ReportExt.al` | `ReportExtension 90300`<br>`APSS Add Item Image Gate` | Extends `Report 30106 "Shpfy Add Item to Shopify"`. Filters `Item` in `OnBeforePreDataItem` (falls back to `'APSS_NO_IMAGE_MATCH'` if none pass) and sanitizes marketing text in `OnBeforeAfterGetRecord`. |
| `ShopifyEnhancements.PermissionSet.al` | `PermissionSet 90300`<br>`APSS SHOPIFY ENH` | Assignable permission set granting RIMD/X permissions on all extension tables, pages, and codeunits. |

---

## 3. Data Mapping & Transformation Rules

| Target (Shopify) | Source (Business Central) | Transformation / Rule |
| :--- | :--- | :--- |
| **Product Title** | `APSS Brand` + `Item.Description` | `Brand + ' ' + Description`. Anti-duplication: if `Description` equals `Brand` or starts with `Brand + ' '` (case-insensitive), `Brand` is not prepended twice. |
| **Product Body HTML** | `Entity Text` (`Marketing Text`) | Embedded base64 images (`data:image...`) stripped. Tab-separated lines (`\t`) converted into 2-column HTML `<table>`. Quotes `"` replaced with `'`, raw `\r`/`\n`/`\t` removed for GraphQL safety. |
| **SEO Title** | `ShopifyProduct.Title` | Truncated to 70 characters. |
| **SEO Description** | `Marketing Text` (fallback `Item.Description`) | HTML tags stripped (`RemoveHtmlTags`), truncated to 160 characters (`...` at 157 if exceeded). |
| **Unit Price & Compare Price** | BC Sales Pricing (`CU 7000` / `CU 7020`) | Temp Sales Quote (`Document Date = WorkDate()`) forced at `Quantity = 1.0`. Converted to Shop Currency (e.g., SGD). `ComparePrice = 0` if `Unit Price <= Line Amount`. |
| **Product Metafield:** `custom.brand` | `GetBrandName(Item)` | `single_line_text_field`. |
| **Product Metafield:** `custom.manufacture_number` | `Item.Description.Trim()` | `single_line_text_field` (aligned with Kathy & June confirmation). |
| **Product Metafield:** `custom.uom` | `Item."Base Unit of Measure"` | `single_line_text_field`. |
| **Product Metafield:** `custom.incoterms` | Fixed `'EXW'` | `single_line_text_field`. |
| **Product Metafield:** `custom.lead_time` | `Item."Lead Time Calculation"` | `number_integer` (`CalcDate(Formula, Today()) - Today()`). Omitted if formula is blank. |
| **Product Metafield:** `custom.price_valid_until` | `Table 90306` (`Ending Date`) | `date` (`YYYY-MM-DD`). Uses captured `Ending Date` if no variant conflict; otherwise defaults to `Today() + 30D`. |
| **Variant Metafield:** `custom.manufacture_number` | `Item.Description.Trim()` | `single_line_text_field`. |
| **Variant Metafields:** `mm-google-shopping.custom_product` & `google.custom_product` | Fixed `'true'` | `boolean`. |
| **Variant Metafields:** `mm-google-shopping.mpn` & `google.mpn` | `Item.Description.Trim()` | `single_line_text_field`. Populated **only** if `Description` is a single token without spaces (`TryExtractCleanPartNumber`); otherwise cleared and logged to `APSS Diagnostic Log`. |

---

## 4. External API Endpoints & Security

| Purpose | Endpoint & Method | Authentication & Location |
| :--- | :--- | :--- |
| **OAuth 2.0 Token Refresh** | `POST https://{shop}.myshopify.com/admin/oauth/access_token`<br>`Content-Type: application/x-www-form-urlencoded`<br>`grant_type=client_credentials` | Uses `Client ID` & `Client Secret` from `IsolatedStorage`. Saves 24h token + expiry back to `IsolatedStorage` (`DataScope::Module`).<br>File: `APSSShopifySKUPrecheck.Codeunit.al` (`RefreshAccessTokenViaOAuth`). |
| **GraphQL SKU Lookup** | `POST https://{shop}.myshopify.com/admin/api/2024-01/graphql.json` | Header: `X-Shopify-Access-Token`. Queries `productVariants(first: 10, query: "sku:\"..\"" )`.<br>File: `APSSShopifySKUPrecheck.Codeunit.al` (`QueryShopifyGraphQLDirectly`). |
| **GraphQL Product Existence Check** | `POST https://{shop}.myshopify.com/admin/api/2024-01/graphql.json` | Header: `X-Shopify-Access-Token`. Queries `product(id: "gid://shopify/Product/...")`.<br>File: `APSSShopifySKUPrecheck.Codeunit.al` (`CheckShopifyProductIdExists`). |
| **Metafields Sync** | Standard Connector (`Shpfy Metafields`) | `ShopifyMetafields.SyncMetafieldsToShopify(...)` dispatches `metafieldsSet` GraphQL mutations.<br>File: `ShopifySyncEvents.Codeunit.al`. |

> **Security Rule:** Never store raw `Client Secret` or `Access Token` in normal BC table fields. `Shpfy Shop` fields `90302` and `90305` are masked (`********************`) in `OnValidate()` and immediately written to `IsolatedStorage`.

---

## 5. Production Setup & Troubleshooting Playbook

### 5.1 Required Configuration in Business Central
1. **Permission Set:** Assign `APSS SHOPIFY ENH` (`90300`) to all users/service accounts running Shopify sync.
2. **Shopify Shop Card (`Shpfy Shop Card`):**
   - Set `APSS Procurement Email` (e.g. `Procurement@apss.com`).
   - Set `APSS Shopify URL` (e.g. `your-store.myshopify.com`).
   - Set `APSS Client ID` and `APSS Client Secret` (or manual Token) and enable `APSS Enable SKU Precheck = true`.
   - Click **Test Shopify Precheck Connection** to verify OAuth + GraphQL ping.
3. **Email Scenario Assignment:** Map `APSS Shopify Procurement` (`90300`) to the company sender email account (e.g. `IT.Support@apss.com`).
4. **Job Queue Entry:**
   - **Object Type to Run:** `Codeunit`
   - **Object ID to Run:** `90306` (`APSS Shopify Auto Sync Job`)
   - **Parameter String:** `<Shop Code>` (or leave blank to use the first `Shpfy Shop`)
   - **Recurrence:** Every 30 minutes (or per operational schedule).

### 5.2 Where to Check Logs When Items Fail
1. **`Shopify Log Entries` (Standard Connector):** Search via Tell Me (`Alt+Q`). Shows exact Shopify API GraphQL/REST errors (e.g., `400 Bad Request`, field validation errors) for items marked `Not updated (Pending review)` in the summary email.
2. **`Shopify Reconcile Log` (`Page 90303`):** Shows items blocked by SKU Precheck (`SKU Collision`, `Missing Product on Shopify`, `Duplicate SKU in Batch`, `Payload Limit Exceeded`). Users can bulk-select and run **Apply Mapping to BC** or **Mark as Resolved**.
3. **`APSS Diagnostic Logs` (`Page 90305`):** Shows chunk failures (`AutoSync:AddItemChunkFailed`, `AutoSync:SyncProductsChunkFailed`), pricing calculation traces, Google MPN omissions, and marketing text sanitization stats.
4. **`Job Queue Log Entries`:** Shows overall Job Queue run status and execution timestamps for Codeunit `90306`.

---

## 6. Known Limitations & Future Upgrade Roadmap

These areas were intentionally scoped or constrained for the `1.0.0.29` Go-Live and are the top candidates for future enhancements:

1. **FactBox Table Lock Contention (`Page 90302` / `CU 90301`):**
   - *Current Behavior:* `CalculateReadinessStatistics` iterates all `Item` records with default isolation. Manually clicking **Refresh Statistics** on the FactBox while Job Queue `90306` is `In Process` can cause SQL lock contention/deadlocks.
   - *Future Upgrade:* Set `ReadIsolation := IsolationLevel::ReadUncommitted` and `Item.SetLoadFields("No.", "APSS Shopify Ready", ...)` inside `CalculateReadinessStatistics`, or cache statistics in a lightweight summary table updated by the Job Queue.
2. **`ItemListShopify` UI Performance (`PageExt 90300`):**
   - *Current Behavior:* `GetItemSyncStatus` runs per visible row on `OnAfterGetRecord`, querying `APSS Shpfy Reconcile Log`, `Shpfy Product`, and `Shpfy Variant`.
   - *Future Upgrade:* Persist the computed `APSS Sync Status` enum onto `Item` during `RefreshItem` / sync events, or use `SetLoadFields` + `ReadUncommitted` to minimize page load latency as the catalog grows beyond 10,000+ items.
3. **GraphQL API Version Lifecycle (`2024-01`):**
   - *Current Behavior:* `APSSShopifySKUPrecheck` hardcodes `/admin/api/2024-01/graphql.json`.
   - *Future Upgrade:* Move the API version string to a configurable field on `APSS Shpfy Shop` (or update to `2025-01` / `2026-01` before Shopify deprecates `2024-01`).
4. **Multi-Shop Support:**
   - *Current Behavior:* `APSS Shpfy Reconcile Log` (`Table 90301`) is keyed by `Entry No.` and deduplicated by `(Item No., SKU, Reason, Resolved)` without a `Shop Code` column; `AutoSync` processes one shop per Job Queue Entry parameter.
   - *Future Upgrade:* Add `Shop Code` to `Table 90301` if APSS expands to multiple independent Shopify storefronts with overlapping SKUs.
5. **Shopify Connector `AddItemImageGate` Filter Length (`ReportExt 90300`):**
   - *Current Behavior:* When triggered manually without chunking on >2,000 eligible items, building `FilterBuilder` with `'ITEM1'|'ITEM2'|...` can approach BC's filter complexity limit (note: `AutoSyncJob 90306` already solves this via 100-item chunking).
   - *Future Upgrade:* Apply the same 100-item chunking loop to the manual `Add Ready Items to Shopify` action in `ItemListShopify.PageExt.al` if users frequently select >1,500 items manually at once.
6. **Direct GraphQL `productUpdate` Error Capture in Email:**
   - *Current Behavior:* When a chunk fails or an item is not updated by `Report 30108`, `APSSShopifyEmailMgt` falls back to `Not updated (Pending review)` because standard Connector logs errors in `Shpfy Log Entry` rather than `APSS Shpfy Reconcile Log`.
   - *Future Upgrade:* Query the latest matching `Shpfy Log Entry` (within the current sync time window) inside `BuildSuccessHtmlBody` to print the exact Shopify GraphQL error message inline in the email's `Details` column.
