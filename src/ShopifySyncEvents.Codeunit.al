namespace Microsoft.Integration.Shopify;

using Microsoft.Inventory.Item;

codeunit 90302 "APSS Shopify Sync Events"
{

    // 2. IMAGE FILTERING — SYNC PRODUCTS FLOW
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnAfterProductsToSynchronizeFiltersSet', '', false, false)]
    local procedure FilterProductsWithoutImageOnSync(
        var ShopifyProduct: Record "Shpfy Product";
        Shop: Record "Shpfy Shop";
        OnlyUpdatePrice: Boolean
    )
    var
        ProductLoop: Record "Shpfy Product";
        Item: Record Item;
        FilterBuilder: TextBuilder;
        ValidProductCount: Integer;
    begin
        ProductLoop.CopyFilters(ShopifyProduct);
        if ProductLoop.FindSet() then
            repeat
                if not IsNullGuid(ProductLoop."Item SystemId") then
                    if Item.GetBySystemId(ProductLoop."Item SystemId") then
                        if Item.Picture.Count() > 0 then begin
                            if FilterBuilder.Length() > 0 then
                                FilterBuilder.Append('|');
                            FilterBuilder.Append(Format(ProductLoop."Item SystemId", 0, 4));
                            ValidProductCount += 1;
                        end;
            until ProductLoop.Next() = 0;

        if ValidProductCount > 0 then
            ShopifyProduct.SetFilter("Item SystemId", FilterBuilder.ToText())
        else
            ShopifyProduct.SetRange("Item SystemId", CreateGuid()); // Block sync completely if no items have pictures
    end;

    // 3A. METAFIELD POPULATION FOR NEW PRODUCTS (ADD ITEMS FLOW)
    [EventSubscriber(ObjectType::Table, Database::"Shpfy Product", 'OnAfterInsertEvent', '', false, false)]
    local procedure OnAfterInsertShopifyProduct(var Rec: Record "Shpfy Product"; RunTrigger: Boolean)
    var
        ShopifyMetafields: Codeunit "Shpfy Metafields";
    begin
        if Rec.IsTemporary() then
            exit;

        if Rec.Id = 0 then
            exit;

        if IsNullGuid(Rec."Item SystemId") then
            exit;

        if Rec."Shop Code" = '' then
            exit;

        if PopulateProductMetafieldRecords(Rec) then
            ShopifyMetafields.SyncMetafieldsToShopify(Database::"Shpfy Product", Rec.Id, Rec."Shop Code");
    end;

    // 3B. METAFIELD POPULATION BEFORE SYNC (EXISTING PRODUCTS FLOW)
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnBeforeUpdateProductMetafields', '', false, false)]
    local procedure AutoPopulateProductMetafields(ProductId: BigInteger)
    var
        ShopifyProduct: Record "Shpfy Product";
    begin
        if ProductId = 0 then
            exit;

        if not ShopifyProduct.Get(ProductId) then
            exit;

        PopulateProductMetafieldRecords(ShopifyProduct);
    end;

    local procedure PopulateProductMetafieldRecords(ShopifyProduct: Record "Shpfy Product"): Boolean
    var
        Item: Record Item;
        ProductTitleCU: Codeunit "APSS Shopify Product Title";
        BrandName: Text;
        VendorItemNo: Text;
        LeadTimeText: Text;
    begin
        if IsNullGuid(ShopifyProduct."Item SystemId") then
            exit(false);

        if not Item.GetBySystemId(ShopifyProduct."Item SystemId") then
            exit(false);

        // brand
        BrandName := ProductTitleCU.GetBrandName(Item);
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'brand', BrandName, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // manufacture_number
        VendorItemNo := ProductTitleCU.GetProductNumber(Item);
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'manufacture_number', VendorItemNo, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // description
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'description', Item.Description, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // uom
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'uom', Item."Base Unit of Measure", Enum::"Shpfy Metafield Type"::single_line_text_field);

        // incoterms
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'incoterms', 'EXW', Enum::"Shpfy Metafield Type"::single_line_text_field);

        // lead_time
        if Format(Item."Lead Time Calculation") <> '' then
            LeadTimeText := Format(CalcDate(Item."Lead Time Calculation", Today()) - Today())
        else
            LeadTimeText := '';
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'lead_time', LeadTimeText, Enum::"Shpfy Metafield Type"::number_integer);

        exit(true);
    end;

    local procedure SetOrUpdateMetafield(
        OwnerId: BigInteger;
        MetafieldNamespace: Text[255];
        MetafieldName: Text[64];
        MetafieldValue: Text;
        MetafieldType: Enum "Shpfy Metafield Type"
    )
    var
        ShopifyMetafield: Record "Shpfy Metafield";
        ParentTableId: Integer;
    begin
        ParentTableId := Database::"Shpfy Product";

        MetafieldValue := MetafieldValue.Trim();
        if MetafieldValue = '' then
            exit;

        if StrLen(MetafieldValue) > MaxStrLen(ShopifyMetafield.Value) then
            MetafieldValue := CopyStr(MetafieldValue, 1, MaxStrLen(ShopifyMetafield.Value));

        ShopifyMetafield.SetRange("Parent Table No.", ParentTableId);
        ShopifyMetafield.SetRange("Owner Id", OwnerId);
        ShopifyMetafield.SetRange(Namespace, MetafieldNamespace);
        ShopifyMetafield.SetRange(Name, MetafieldName);

        if ShopifyMetafield.FindFirst() then begin
            if (ShopifyMetafield.Value <> MetafieldValue) or (ShopifyMetafield.Type <> MetafieldType) then begin
                ShopifyMetafield.Value := MetafieldValue;
                ShopifyMetafield.Type := MetafieldType;
                ShopifyMetafield."Last Updated by BC" := CurrentDateTime;
                ShopifyMetafield.Modify(true);
            end;
        end else begin
            Clear(ShopifyMetafield);
            ShopifyMetafield.Validate("Parent Table No.", ParentTableId);
            ShopifyMetafield."Owner Id" := OwnerId;
            ShopifyMetafield.Namespace := MetafieldNamespace;
            ShopifyMetafield.Name := MetafieldName;
            ShopifyMetafield.Value := MetafieldValue;
            ShopifyMetafield.Type := MetafieldType;
            ShopifyMetafield."Last Updated by BC" := CurrentDateTime;
            ShopifyMetafield.Insert(true);
        end;
    end;
}
