namespace Microsoft.Integration.Shopify;

using Microsoft.Inventory.Item;

page 90300 "APSS Shopify Item Selection"
{
    PageType = List;
    Caption = 'Shopify Item Selection';
    SourceTable = "APSS Shpfy Item Sel. Buffer";
    SourceTableTemporary = true;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(Selected; Rec.Selected)
                {
                    ApplicationArea = All;
                    Caption = 'Select';
                    Editable = true;
                    ToolTip = 'Specifies whether this item should be exported to Shopify.';
                }
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    Editable = false;
                }
                field("Has Shopify Image"; Rec."Has Shopify Image")
                {
                    ApplicationArea = All;
                    Editable = false;
                }
                field("Shopify Ready"; Rec."Shopify Ready")
                {
                    ApplicationArea = All;
                    Editable = false;
                }
                field("Sync Status"; Rec."Sync Status")
                {
                    ApplicationArea = All;
                    Caption = 'Shopify Sync Status';
                    Editable = false;
                    StyleExpr = Rec."Sync Status Style";
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action("Select All")
            {
                ApplicationArea = All;
                Caption = 'Select All';
                Image = Approve;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Selects all eligible items in the list.';

                trigger OnAction()
                begin
                    SetAllInclusion(true);
                end;
            }
            action("Deselect All")
            {
                ApplicationArea = All;
                Caption = 'Deselect All';
                Image = Cancel;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Deselects all items in the list.';

                trigger OnAction()
                begin
                    SetAllInclusion(false);
                end;
            }
        }
    }

    procedure SetItems(var InItem: Record Item)
    var
        ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
    begin
        Rec.Reset();
        Rec.DeleteAll();

        if InItem.FindSet() then
            repeat
                Rec.Init();
                Rec."Item No." := InItem."No.";
                Rec.Selected := true;
                Rec.Description := InItem.Description;
                Rec."Has Shopify Image" := InItem."APSS Has Shopify Image";
                Rec."Shopify Ready" := InItem."APSS Shopify Ready";
                Rec."Sync Status" := ShopifyReadinessMgt.GetItemSyncStatus(InItem);
                Rec."Sync Status Style" := ShopifyReadinessMgt.GetSyncStatusStyle(InItem);
                Rec.Insert();
            until InItem.Next() = 0;
    end;

    procedure GetSelectedItems(var OutItem: Record Item temporary)
    var
        ActualItem: Record Item;
    begin
        OutItem.Reset();
        OutItem.DeleteAll();

        Rec.Reset();
        Rec.SetRange(Selected, true);
        if Rec.FindSet() then
            repeat
                if ActualItem.Get(Rec."Item No.") then begin
                    OutItem := ActualItem;
                    OutItem.Insert();
                end;
            until Rec.Next() = 0;
        Rec.Reset();
    end;

    local procedure SetAllInclusion(Value: Boolean)
    begin
        Rec.Reset();
        if Rec.FindSet(true) then
            repeat
                Rec.Selected := Value;
                Rec.Modify();
            until Rec.Next() = 0;

        CurrPage.Update(false);
    end;
}
