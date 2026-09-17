codeunit 90301 "APSS Shopify Readiness Mgt."
{
    procedure RefreshItem(var Item: Record Item)
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
        if ProductTitleMgt.GetCustomerItemReference(Item) = '' then
            AddMessage(MissingInformation, 'Missing Customer Reference No.');
        if Item."Base Unit of Measure" = '' then
            AddMessage(MissingInformation, 'Missing Base Unit of Measure');

        Item."APSS Has Shopify Image" := HasImage;
        Item."APSS Shopify Ready" := MissingInformation = '';
        Item."APSS Shopify Validation" := MissingInformation;
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

    procedure GetItemSyncStatus(Item: Record Item): Enum "APSS Shopify Item Sync Status"
    var
        ShpfyProduct: Record "Shpfy Product";
    begin
        if not (Item."APSS Has Shopify Image" and Item."APSS Shopify Ready") then
            exit(Enum::"APSS Shopify Item Sync Status"::"Not Ready");

        ShpfyProduct.SetRange("Item SystemId", Item.SystemId);
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
            else
                exit('Standard');
        end;
    end;

    local procedure AddMessage(var ExistingMessage: Text[250]; NewMessage: Text)
    begin
        if ExistingMessage = '' then
            ExistingMessage := CopyStr(NewMessage, 1, MaxStrLen(ExistingMessage))
        else
            ExistingMessage := CopyStr(ExistingMessage + '; ' + NewMessage, 1, MaxStrLen(ExistingMessage));
    end;
}
