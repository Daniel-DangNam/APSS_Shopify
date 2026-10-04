namespace APSS.Shopify;

using Microsoft.Inventory.Item;

page 90302 "APSS Shpfy Readiness FactBox"
{
    PageType = CardPart;
    ApplicationArea = All;
    Caption = 'Shopify Readiness Statistics';

    layout
    {
        area(Content)
        {
            group("1. Total Items")
            {
                Caption = '1. Inventory Scope';

                field(TotalItems; TotalItems)
                {
                    ApplicationArea = All;
                    Caption = 'Total Items in BC';
                    ToolTip = 'Total number of items in Business Central.';
                    Editable = false;
                }
            }
            group("2. Eligible Items")
            {
                Caption = '2. Shopify Eligible Items';

                field(TotalEligible; TotalEligible)
                {
                    ApplicationArea = All;
                    Caption = 'Total Eligible';
                    ToolTip = 'Total items meeting Shopify readiness criteria.';
                    Editable = false;
                    Style = Favorable;
                    StyleExpr = true;
                }
                field(NewReady; NewReady)
                {
                    ApplicationArea = All;
                    Caption = '  - 2.1. New Ready';
                    ToolTip = 'New items ready to be created on Shopify.';
                    Editable = false;
                    Style = Strong;
                    StyleExpr = true;
                }
                field(ModifiedReady; ModifiedReady)
                {
                    ApplicationArea = All;
                    Caption = '  - 2.2. Modified Ready';
                    ToolTip = 'Modified items ready to be updated on Shopify.';
                    Editable = false;
                    Style = Attention;
                    StyleExpr = true;
                }
                field(Synced; Synced)
                {
                    ApplicationArea = All;
                    Caption = '  - 2.3. Synced to Shopify';
                    ToolTip = 'Items already exported to Shopify without pending local changes.';
                    Editable = false;
                    Style = Subordinate;
                    StyleExpr = true;
                }
            }
            group("3. Ineligible Items")
            {
                Caption = '3. Not Eligible';

                field(NotReady; NotReady)
                {
                    ApplicationArea = All;
                    Caption = 'Not Ready (Missing Data)';
                    ToolTip = 'Items missing approval, image, brand, or master data.';
                    Editable = false;
                    Style = Unfavorable;
                    StyleExpr = true;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RefreshStatistics)
            {
                ApplicationArea = All;
                Caption = 'Refresh Statistics';
                Image = Refresh;
                ToolTip = 'Recalculates the Shopify readiness statistics.';

                trigger OnAction()
                begin
                    CalculateStats();
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        CalculateStats();
    end;

    var
        TotalItems: Integer;
        TotalEligible: Integer;
        NewReady: Integer;
        ModifiedReady: Integer;
        Synced: Integer;
        NotReady: Integer;

    local procedure CalculateStats()
    var
        ReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
    begin
        ReadinessMgt.CalculateReadinessStatistics(TotalItems, TotalEligible, NewReady, ModifiedReady, Synced, NotReady);
    end;
}
