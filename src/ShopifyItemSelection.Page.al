namespace APSS.Shopify;

using Microsoft.Integration.Shopify;
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
            group(QuickSelectionGroup)
            {
                Caption = 'Quick Filter & Batch Selection';
                field(SyncTypeFilterField; SyncTypeFilter)
                {
                    ApplicationArea = All;
                    Caption = 'Sync Type Filter';
                    OptionCaption = 'All (New & Modified),New Ready Only,Modified Ready Only';
                    ToolTip = 'Filters and selects items by their Shopify readiness sync status.';

                    trigger OnValidate()
                    begin
                        ApplyQuickFilterAndQuantity();
                    end;
                }
                field(BatchQuantityField; BatchQuantity)
                {
                    ApplicationArea = All;
                    Caption = 'Batch Quantity (0 = All)';
                    MinValue = 0;
                    ToolTip = 'Specifies the maximum number of items to select for the chosen sync type. Enter 0 to select all matching items.';

                    trigger OnValidate()
                    begin
                        ApplyQuickFilterAndQuantity();
                    end;
                }
            }
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
            action("Apply Quick Select")
            {
                ApplicationArea = All;
                Caption = 'Apply Quick Select';
                Image = Filter;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Applies the selected sync type filter and batch quantity.';

                trigger OnAction()
                begin
                    ApplyQuickFilterAndQuantity();
                end;
            }
            action("Select New Ready (Batch)")
            {
                ApplicationArea = All;
                Caption = 'Select New Ready';
                Image = NewDocument;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Selects only items with New Ready sync status based on the batch quantity.';

                trigger OnAction()
                begin
                    SyncTypeFilter := SyncTypeFilter::"New Ready Only";
                    ApplyQuickFilterAndQuantity();
                end;
            }
            action("Select Modified Ready (Batch)")
            {
                ApplicationArea = All;
                Caption = 'Select Modified Ready';
                Image = Edit;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Selects only items with Modified Ready sync status based on the batch quantity.';

                trigger OnAction()
                begin
                    SyncTypeFilter := SyncTypeFilter::"Modified Ready Only";
                    ApplyQuickFilterAndQuantity();
                end;
            }
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
                    SyncTypeFilter := SyncTypeFilter::All;
                    BatchQuantity := 0;
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

    var
        SyncTypeFilter: Option All,"New Ready Only","Modified Ready Only";
        BatchQuantity: Integer;

    procedure SetItems(var InItem: Record Item)
    var
        ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
    begin
        Rec.Reset();
        Rec.DeleteAll();
        SyncTypeFilter := SyncTypeFilter::All;
        BatchQuantity := 0;

        if InItem.FindSet() then
            repeat
                Rec.Init();
                Rec."Item No." := InItem."No.";
                Rec.Selected := true;
                Rec.Description := InItem.Description;
                Rec."Sync Status" := ShopifyReadinessMgt.GetItemSyncStatus(InItem);
                Rec."Has Shopify Image" := InItem."APSS Has Shopify Image";
                Rec."Shopify Ready" := InItem."APSS Shopify Ready";
                Rec."Sync Status Style" := ShopifyReadinessMgt.GetSyncStatusStyle(InItem);
                Rec.Insert();
            until InItem.Next() = 0;
    end;

    procedure GetSelectedItems(var OutItem: Record Item temporary)
    var
        ActualItem: Record Item;
        SKUPrecheckCU: Codeunit "APSS Shopify SKU Precheck";
    begin
        OutItem.Reset();
        OutItem.DeleteAll();

        Rec.Reset();
        Rec.SetRange(Selected, true);
        if Rec.FindSet() then
            repeat
                if ActualItem.Get(Rec."Item No.") then begin
                    SKUPrecheckCU.SanitizeItemMarketingText(ActualItem);
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

    local procedure ApplyQuickFilterAndQuantity()
    var
        SelectedCount: Integer;
        Match: Boolean;
    begin
        Rec.Reset();
        if Rec.FindSet(true) then
            repeat
                Match := false;
                case SyncTypeFilter of
                    SyncTypeFilter::All:
                        Match := true;
                    SyncTypeFilter::"New Ready Only":
                        Match := (Rec."Sync Status" = Enum::"APSS Shopify Item Sync Status"::"New Ready");
                    SyncTypeFilter::"Modified Ready Only":
                        Match := (Rec."Sync Status" = Enum::"APSS Shopify Item Sync Status"::"Modified Ready");
                end;

                if Match then begin
                    if (BatchQuantity = 0) or (SelectedCount < BatchQuantity) then begin
                        Rec.Selected := true;
                        SelectedCount += 1;
                    end else
                        Rec.Selected := false;
                end else
                    Rec.Selected := false;

                Rec.Modify();
            until Rec.Next() = 0;

        CurrPage.Update(false);
    end;
}
