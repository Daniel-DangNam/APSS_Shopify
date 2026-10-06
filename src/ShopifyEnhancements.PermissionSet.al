permissionset 90300 "APSS SHOPIFY ENH"
{
    Assignable = true;
    Caption = 'APSS Shopify Enhancements';

    Permissions =
        tabledata Item = RM,
        tabledata "Shpfy Product" = RIMD,
        tabledata "Shpfy Variant" = RIMD,
        tabledata "Shpfy Metafield" = RIMD,
        tabledata "APSS Diagnostic Log" = RIMD,
        tabledata "APSS Item Price Ending Date" = RIMD,
        tabledata "APSS Shpfy Reconcile Log" = RIMD,
        table "APSS Shpfy Reconcile Log" = X,
        codeunit "APSS Shopify Product Title" = X,
        codeunit "APSS Shopify Readiness Mgt." = X,
        codeunit "APSS Shopify Sync Events" = X,
        codeunit "APSS Shopify Email Mgt." = X,
        codeunit "APSS Shopify SKU Precheck" = X,
        page "APSS Diagnostic Logs" = X,
        page "APSS Shopify Item Selection" = X,
        page "APSS Shpfy Readiness FactBox" = X,
        page "APSS Shpfy Reconcile Log" = X;
}
