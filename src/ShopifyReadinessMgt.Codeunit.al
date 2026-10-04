codeunit 90301 "APSS Shopify Readiness Mgt."
{
    procedure EvaluateItemReadiness(var Item: Record Item)
    var
        ProductTitleMgt: Codeunit "APSS Shopify Product Title";
        MissingInformation: Text[250];
        HasImage: Boolean;
    begin
        HasImage := Item.Picture.Count() > 0;

        if not ProductTitleMgt.IsItemApproved(Item) then
            AddMessage(MissingInformation, 'Item is not APSS Approved');
        if not HasImage then
            AddMessage(MissingInformation, 'Missing image');
        if ProductTitleMgt.GetBrandName(Item) = '' then
            AddMessage(MissingInformation, 'Missing brand');
        if Item.Description.Trim() = '' then
            AddMessage(MissingInformation, 'Missing Description');
        if Item."Base Unit of Measure" = '' then
            AddMessage(MissingInformation, 'Missing Base Unit of Measure');

        Item."APSS Has Shopify Image" := HasImage;
        Item."APSS Shopify Ready" := MissingInformation = '';
        Item."APSS Shopify Validation" := MissingInformation;
    end;

    procedure RefreshItem(var Item: Record Item)
    begin
        EvaluateItemReadiness(Item);
        Item.Modify(false);
    end;

    procedure RefreshAllItems()
    var
        Item: Record Item;
        UpdatedCount: Integer;
    begin
        if Item.FindSet(true) then
            repeat
                RefreshItem(Item);
                UpdatedCount += 1;
            until Item.Next() = 0;

        Message('%1 items were checked for Shopify readiness.', UpdatedCount);
    end;

    procedure RefreshAllItemsQuiet()
    var
        Item: Record Item;
    begin
        if Item.FindSet(true) then
            repeat
                RefreshItem(Item);
            until Item.Next() = 0;
    end;

    procedure RefreshSelectedItems(var SelectedItem: Record Item)
    var
        UpdatedCount: Integer;
    begin
        if SelectedItem.FindSet(true) then
            repeat
                RefreshItem(SelectedItem);
                UpdatedCount += 1;
            until SelectedItem.Next() = 0;

        Message('%1 selected item(s) were checked for Shopify readiness.', UpdatedCount);
    end;

    procedure IsItemReady(var Item: Record Item): Boolean
    begin
        EvaluateItemReadiness(Item);
        exit(Item."APSS Shopify Ready");
    end;

    procedure GetItemSyncStatus(var Item: Record Item): Enum "APSS Shopify Item Sync Status"
    var
        ShpfyProduct: Record "Shpfy Product";
        ShopifyShop: Record "Shpfy Shop";
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        if not IsItemReady(Item) then
            exit(Enum::"APSS Shopify Item Sync Status"::"Not Ready");

        // Check if item has unresolved reconciliation / conflict issues
        ReconcileLog.SetRange("Item No.", Item."No.");
        ReconcileLog.SetRange(Resolved, false);
        if not ReconcileLog.IsEmpty() then
            exit(Enum::"APSS Shopify Item Sync Status"::"Needs Reconciliation");

        ShpfyProduct.SetRange("Item SystemId", Item.SystemId);
        ShpfyProduct.SetFilter(Id, '<>0');
        if ShopifyShop.FindFirst() then
            ShpfyProduct.SetRange("Shop Code", ShopifyShop.Code);

        if not ShpfyProduct.FindFirst() then
            exit(Enum::"APSS Shopify Item Sync Status"::"New Ready");

        if Item.SystemModifiedAt > ShpfyProduct.SystemModifiedAt then
            exit(Enum::"APSS Shopify Item Sync Status"::"Modified Ready");

        exit(Enum::"APSS Shopify Item Sync Status"::"Synced Unchanged");
    end;

    procedure GetSyncStatusStyle(Item: Record Item): Text
    begin
        case GetItemSyncStatus(Item) of
            Enum::"APSS Shopify Item Sync Status"::"New Ready":
                exit('Strong');
            Enum::"APSS Shopify Item Sync Status"::"Modified Ready":
                exit('Attention');
            Enum::"APSS Shopify Item Sync Status"::"Synced Unchanged":
                exit('Subordinate');
            Enum::"APSS Shopify Item Sync Status"::"Needs Reconciliation":
                exit('Unfavorable');
            else
                exit('Standard');
        end;
    end;

    procedure CalculateReadinessStatistics(
        var TotalItems: Integer;
        var TotalEligible: Integer;
        var NewReady: Integer;
        var ModifiedReady: Integer;
        var Synced: Integer;
        var NotReady: Integer
    )
    var
        Item: Record Item;
        Status: Enum "APSS Shopify Item Sync Status";
    begin
        TotalItems := 0;
        TotalEligible := 0;
        NewReady := 0;
        ModifiedReady := 0;
        Synced := 0;
        NotReady := 0;

        if Item.FindSet() then
            repeat
                TotalItems += 1;
                Status := GetItemSyncStatus(Item);
                case Status of
                    Enum::"APSS Shopify Item Sync Status"::"New Ready":
                        begin
                            NewReady += 1;
                            TotalEligible += 1;
                        end;
                    Enum::"APSS Shopify Item Sync Status"::"Modified Ready":
                        begin
                            ModifiedReady += 1;
                            TotalEligible += 1;
                        end;
                    Enum::"APSS Shopify Item Sync Status"::"Synced Unchanged":
                        begin
                            Synced += 1;
                            TotalEligible += 1;
                        end;
                    else
                        NotReady += 1;
                end;
            until Item.Next() = 0;
    end;

    local procedure AddMessage(var ExistingMessage: Text[250]; NewMessage: Text)
    begin
        if ExistingMessage = '' then
            ExistingMessage := CopyStr(NewMessage, 1, MaxStrLen(ExistingMessage))
        else
            ExistingMessage := CopyStr(ExistingMessage + '; ' + NewMessage, 1, MaxStrLen(ExistingMessage));
    end;
}
