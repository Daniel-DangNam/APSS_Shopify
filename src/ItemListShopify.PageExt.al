pageextension 90300 "APSS Item List Shopify" extends "Item List"
{
    layout
    {
        addafter(Description)
        {
            field("APSS Has Shopify Image"; Rec."APSS Has Shopify Image")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies whether the item has a Business Central item picture for Shopify.';
            }
            field("APSS Shopify Ready"; Rec."APSS Shopify Ready")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies whether the item has the minimum information required for Shopify.';
            }
            field("APSS Shopify Validation"; Rec."APSS Shopify Validation")
            {
                ApplicationArea = All;
                ToolTip = 'Shows the information that must be completed before the item is exported to Shopify.';
            }
        }
    }

    actions
    {
        addlast(Processing)
        {

            action("Refresh Selected Shopify Readiness")
            {
                ApplicationArea = All;
                Caption = 'Refresh Selected Shopify Readiness';
                Image = Refresh;
                ToolTip = 'Checks Shopify readiness for the selected item lines.';

                trigger OnAction()
                var
                    SelectedItem: Record Item;
                    ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
                begin
                    CurrPage.SetSelectionFilter(SelectedItem);
                    ShopifyReadinessMgt.RefreshSelectedItems(SelectedItem);
                    CurrPage.Update(false);
                end;
            }
            action("Refresh All Shopify Readiness")
            {
                ApplicationArea = All;
                Caption = 'Refresh All Shopify Readiness';
                Image = RefreshLines;
                ToolTip = 'Checks Shopify readiness for all items.';

                trigger OnAction()
                var
                    ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
                begin
                    ShopifyReadinessMgt.RefreshAllItems();
                    CurrPage.Update(false);
                end;
            }
        }
    }
}
