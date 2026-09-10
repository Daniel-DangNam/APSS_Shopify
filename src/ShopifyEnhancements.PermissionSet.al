permissionset 90300 "APSS SHOPIFY ENH"
{
    Assignable = true;
    Caption = 'APSS Shopify Enhancements';

    Permissions =
        tabledata Item = RM,
        tabledata "Shpfy Product" = R,
        tabledata "Shpfy Metafield" = RIMD,
        codeunit "APSS Shopify Product Title" = X,
        codeunit "APSS Shopify Readiness Mgt." = X,
        codeunit "APSS Shopify Sync Events" = X;
}

