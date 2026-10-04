namespace APSS.Shopify;

using Microsoft.Integration.Shopify;

tableextension 90301 "APSS Shpfy Shop" extends "Shpfy Shop"
{
    fields
    {
        field(90300; "APSS Procurement Email"; Text[250])
        {
            Caption = 'Procurement Email';
            ExtendedDatatype = EMail;
            ToolTip = 'Specifies the email address of the procurement team to notify upon Shopify synchronization.';
        }
        field(90301; "APSS Shopify URL"; Text[250])
        {
            Caption = 'Shopify Store URL';
            ExtendedDatatype = URL;
            ToolTip = 'Specifies the Shopify myshopify.com URL for GraphQL API queries.';
        }
        field(90302; "APSS Shopify Token"; Text[250])
        {
            Caption = 'Precheck Access Token';
            ExtendedDatatype = Masked;
            ToolTip = 'Specifies the Shopify Admin API Access Token for SKU GraphQL precheck.';

            trigger OnValidate()
            var
                SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
            begin
                if "APSS Shopify Token" <> '' then begin
                    SKUPrecheck.SetShopifyAccessToken(Rec.Code, "APSS Shopify Token");
                    "APSS Shopify Token" := '********************';
                end;
            end;
        }
        field(90303; "APSS Enable SKU Precheck"; Boolean)
        {
            Caption = 'Enable SKU Precheck';
            InitValue = true;
            ToolTip = 'Specifies if SKU precheck against Shopify Admin is performed before exporting items.';
        }
        field(90304; "APSS Client ID"; Text[100])
        {
            Caption = 'Client ID';
            ToolTip = 'Specifies the Shopify App Client ID for OAuth client-credentials access token refresh.';

            trigger OnValidate()
            var
                SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
            begin
                SKUPrecheck.SetShopifyClientId(Rec.Code, "APSS Client ID");
            end;
        }
        field(90305; "APSS Client Secret"; Text[100])
        {
            Caption = 'Client Secret';
            ExtendedDatatype = Masked;
            ToolTip = 'Specifies the Shopify App Client Secret for OAuth client-credentials access token refresh.';

            trigger OnValidate()
            var
                SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
            begin
                if "APSS Client Secret" <> '' then begin
                    SKUPrecheck.SetShopifyClientSecret(Rec.Code, "APSS Client Secret");
                    "APSS Client Secret" := '********************';
                end;
            end;
        }
    }
}


