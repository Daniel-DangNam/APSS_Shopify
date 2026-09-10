codeunit 90300 "APSS Shopify Product Title"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", OnAfterFillInShopifyProductFields, '', false, false)]
    local procedure SetShopifyProductTitle(Item: Record Item; var ShopifyProduct: Record "Shpfy Product")
    var
        ShopifyTitle: Text;
    begin
        ShopifyTitle := JoinTitlePart(ShopifyTitle, GetBrandName(Item));
        ShopifyTitle := JoinTitlePart(ShopifyTitle, GetProductNumber(Item));
        ShopifyTitle := JoinTitlePart(ShopifyTitle, Item.Description);

        ShopifyProduct.Title := CopyStr(ShopifyTitle, 1, MaxStrLen(ShopifyProduct.Title));

        if not ShopifyProduct.IsTemporary() then
            ShopifyProduct.Modify();
    end;

    procedure GetBrandName(Item: Record Item): Text
    var
        ItemRecRef: RecordRef;
        FldRef: FieldRef;
        FieldRec: Record Field;
    begin
        // Read the APSS Brand value dynamically from the Item record
        ItemRecRef.GetTable(Item);
        FieldRec.SetRange(TableNo, Database::Item);
        FieldRec.SetFilter(FieldName, '%1|%2|%3|%4', 'Brand Code', 'Brand', 'Brand Name', 'APSS Brand*');
        if FieldRec.FindFirst() then begin
            FldRef := ItemRecRef.Field(FieldRec."No.");
            exit(Format(FldRef.Value).Trim());
        end;

        exit('');
    end;

    procedure GetProductNumber(Item: Record Item): Text
    begin
        // Standalone default: Vendor Item No. represents the customer-facing part number.
        // Replace this with the APSS Manufacturer Part No. field if required.
        exit(Item."Vendor Item No.");
    end;

    local procedure JoinTitlePart(CurrentTitle: Text; NewPart: Text): Text
    begin
        NewPart := NewPart.Trim();

        if NewPart = '' then
            exit(CurrentTitle);

        if CurrentTitle = '' then
            exit(NewPart);

        exit(CurrentTitle + ' - ' + NewPart);
    end;
}
