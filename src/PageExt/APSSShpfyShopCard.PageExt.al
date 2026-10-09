namespace APSS.Shopify;

using Microsoft.Integration.Shopify;

pageextension 90301 "APSS Shpfy Shop Card" extends "Shpfy Shop Card"
{
    layout
    {
        addlast(General)
        {
            field("APSS Procurement Email"; Rec."APSS Procurement Email")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the email address of the procurement team to notify upon Shopify synchronization.';
            }
            field("APSS Shopify URL"; Rec."APSS Shopify URL")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the Shopify store myshopify.com URL for GraphQL API SKU precheck.';
            }
            field("APSS Client ID"; Rec."APSS Client ID")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the Shopify App Client ID for automatic OAuth token refresh.';
            }
            field("APSS Client Secret"; Rec."APSS Client Secret")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the Shopify App Client Secret for automatic OAuth token refresh.';
            }
            field("APSS Shopify Token"; Rec."APSS Shopify Token")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the manual Shopify Admin API Access Token (optional if Client ID/Secret is provided).';
            }
            field("APSS Enable SKU Precheck"; Rec."APSS Enable SKU Precheck")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies if SKU precheck against Shopify Admin is performed before exporting items.';
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            action(TestShopifyPrecheckConnection)
            {
                ApplicationArea = All;
                Caption = 'Test Shopify Precheck Connection';
                Image = TestReport;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Tests OAuth token exchange and GraphQL connectivity with Shopify Admin.';

                trigger OnAction()
                var
                    SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
                begin
                    SKUPrecheck.TestShopifyConnection(Rec.Code);
                end;
            }
        }
    }
}

