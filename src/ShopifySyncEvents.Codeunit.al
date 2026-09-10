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

    // 3. METAFIELD POPULATION BEFORE SYNC
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnBeforeUpdateProductMetafields', '', false, false)]
    local procedure AutoPopulateProductMetafields(ProductId: BigInteger)
    var
        ShopifyProduct: Record "Shpfy Product";
        Item: Record Item;
        ProductTitleCU: Codeunit "APSS Shopify Product Title";
        BrandName: Text;
        VendorItemNo: Text;
        LeadTimeText: Text;
    begin
        if ProductId = 0 then
            exit;

        if not ShopifyProduct.Get(ProductId) then
            exit;

        if IsNullGuid(ShopifyProduct."Item SystemId") then
            exit;

        if not Item.GetBySystemId(ShopifyProduct."Item SystemId") then
            exit;

        // brand
        BrandName := ProductTitleCU.GetBrandName(Item);
        SetOrUpdateMetafield(ProductId, 'custom', 'brand', BrandName, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // manufacture_number
        VendorItemNo := ProductTitleCU.GetProductNumber(Item);
        SetOrUpdateMetafield(ProductId, 'custom', 'manufacture_number', VendorItemNo, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // description
        SetOrUpdateMetafield(ProductId, 'custom', 'description', Item.Description, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // uom
        SetOrUpdateMetafield(ProductId, 'custom', 'uom', Item."Base Unit of Measure", Enum::"Shpfy Metafield Type"::single_line_text_field);

        // incoterms
        SetOrUpdateMetafield(ProductId, 'custom', 'incoterms', 'EXW', Enum::"Shpfy Metafield Type"::single_line_text_field);

        // lead_time
        if Format(Item."Lead Time Calculation") <> '' then
            LeadTimeText := Format(Item."Lead Time Calculation")
        else
            LeadTimeText := '';
        SetOrUpdateMetafield(ProductId, 'custom', 'lead_time', LeadTimeText, Enum::"Shpfy Metafield Type"::single_line_text_field);
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
