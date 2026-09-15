namespace Microsoft.Integration.Shopify;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Item.Catalog;
using System.Reflection;

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
        // Standard BC field used for product part number mapping.
        // If a dedicated APSS Manufacturer Part No. field is confirmed, update here.
        exit(Item."Vendor Item No.");
    end;

    procedure GetCustomerItemReference(Item: Record Item): Text
    var
        ItemReference: Record "Item Reference";
    begin
        if Item."No." = '' then
            exit('');

        ItemReference.SetRange("Item No.", Item."No.");
        ItemReference.SetRange("Reference Type", Enum::"Item Reference Type"::Customer);
        if ItemReference.FindFirst() then
            exit(ItemReference."Reference No.");

        exit('');
    end;

    procedure IsItemApproved(Item: Record Item): Boolean
    var
        ItemRecRef: RecordRef;
        FldRef: FieldRef;
        FieldRec: Record Field;
    begin
        if IsNullGuid(Item.SystemId) then
            exit(false);

        FieldRec.SetRange(TableNo, Database::Item);
        FieldRec.SetRange(FieldName, 'APSS Approved');
        FieldRec.SetRange(Type, FieldRec.Type::Boolean);
        if not FieldRec.FindFirst() then
            exit(false);

        ItemRecRef.Open(Database::Item);
        if ItemRecRef.Get(Item.RecordId) then begin
            FldRef := ItemRecRef.Field(FieldRec."No.");
            exit(FldRef.Value());
        end;

        exit(false);
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
