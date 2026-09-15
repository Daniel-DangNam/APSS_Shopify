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

    local procedure AddMessage(var ExistingMessage: Text[250]; NewMessage: Text)
    begin
        if ExistingMessage = '' then
            ExistingMessage := CopyStr(NewMessage, 1, MaxStrLen(ExistingMessage))
        else
            ExistingMessage := CopyStr(ExistingMessage + '; ' + NewMessage, 1, MaxStrLen(ExistingMessage));
    end;
}
