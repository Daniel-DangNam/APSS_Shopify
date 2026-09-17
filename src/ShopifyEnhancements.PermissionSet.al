permissionset 90300 "APSS SHOPIFY ENH"
{
    Assignable = true;
    Caption = 'APSS Shopify Enhancements';

    Permissions =
        tabledata Item = RM,
        tabledata "Shpfy Product" = R,
        tabledata "Shpfy Metafield" = RIMD,
        tabledata "APSS Diagnostic Log" = RIMD,
        tabledata "APSS Item Price Ending Date" = RIMD,
        codeunit "APSS Shopify Product Title" = X,
        codeunit "APSS Shopify Readiness Mgt." = X,
        codeunit "APSS Shopify Sync Events" = X,
        page "APSS Diagnostic Logs" = X;
}

