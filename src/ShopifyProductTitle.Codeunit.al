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
        Brand: Text;
        Desc: Text;
        BrandUpper: Text;
        DescUpper: Text;
    begin
        Brand := GetBrandName(Item);
        Desc := Item.Description.Trim();

        if Brand = '' then
            ShopifyTitle := Desc
        else if Desc = '' then
            ShopifyTitle := Brand
        else begin
            BrandUpper := Brand.ToUpper();
            DescUpper := Desc.ToUpper();
            if (DescUpper = BrandUpper) or
               ((StrLen(DescUpper) > StrLen(BrandUpper)) and (CopyStr(DescUpper, 1, StrLen(BrandUpper) + 1) = (BrandUpper + ' ')))
            then
                ShopifyTitle := Desc
            else
                ShopifyTitle := Brand + ' ' + Desc;
        end;

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
        FieldRec.SetRange(FieldName, 'APSS Brand');
        if not FieldRec.FindFirst() then begin
            FieldRec.SetRange(FieldName, 'Brand Code');
            if not FieldRec.FindFirst() then
                FieldRec.SetRange(FieldName, 'Brand');
        end;
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
        if not FieldRec.FindFirst() then begin
            FieldRec.SetRange(FieldName, 'Approved');
            if not FieldRec.FindFirst() then
                FieldRec.SetRange(FieldName, 'APSS Shopify Approved');
        end;

        if FieldRec.FindFirst() then begin
            ItemRecRef.Open(Database::Item);
            if ItemRecRef.Get(Item.RecordId) then begin
                FldRef := ItemRecRef.Field(FieldRec."No.");
                exit(FldRef.Value());
            end;
        end;

        exit(true);
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
