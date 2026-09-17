namespace Microsoft.Integration.Shopify;

using Microsoft.Inventory.Item;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.Pricing;
using Microsoft.Pricing.PriceList;

codeunit 90302 "APSS Shopify Sync Events"
{
    SingleInstance = true;

    var
        IsCalculatingPrice: Boolean;
        CurrentCalcItemNo: Code[20];
        CurrentCalcShopCode: Code[20];
        CurrentCalcVariantCode: Code[20];
        CurrentCalcEndingDate: Date;
        CurrentCalcBestUnitPrice: Decimal;

    local procedure LogDiag(
        Context: Text[100];
        ItemNo: Code[20];
        ShopCode: Code[20];
        EventCalled: Boolean;
        CalcSucceeded: Boolean;
        CalculatedPrice: Decimal;
        CapturedEndingDate: Date;
        ErrText: Text;
        DetailsText: Text[250]
    )
    var
        DiagLog: Record "APSS Diagnostic Log";
    begin
        Clear(DiagLog);
        DiagLog."Date Time" := CurrentDateTime;
        DiagLog."Session ID" := SessionId();
        DiagLog.Context := Context;
        DiagLog."Item No." := ItemNo;
        DiagLog."Shop Code" := ShopCode;
        DiagLog."Event Called" := EventCalled;
        DiagLog."Calc Succeeded" := CalcSucceeded;
        DiagLog."Calculated Price" := CalculatedPrice;
        DiagLog."Captured Ending Date" := CapturedEndingDate;
        DiagLog."Error Text" := CopyStr(ErrText, 1, MaxStrLen(DiagLog."Error Text"));
        DiagLog.Details := CopyStr(DetailsText, 1, MaxStrLen(DiagLog.Details));
        DiagLog.Insert(true);
    end;

    // 2. APPROVAL & IMAGE FILTERING — SYNC PRODUCTS FLOW
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnAfterProductsToSynchronizeFiltersSet', '', false, false)]
    local procedure FilterProductsWithoutImageOnSync(
        var ShopifyProduct: Record "Shpfy Product";
        Shop: Record "Shpfy Shop";
        OnlyUpdatePrice: Boolean
    )
    var
        ProductLoop: Record "Shpfy Product";
        Item: Record Item;
        StagingRec: Record "APSS Item Price Ending Date";
        ProductTitleCU: Codeunit "APSS Shopify Product Title";
        FilterBuilder: TextBuilder;
        ValidProductCount: Integer;
    begin
        IsCalculatingPrice := false;
        CurrentCalcItemNo := '';
        CurrentCalcShopCode := '';
        CurrentCalcVariantCode := '';
        CurrentCalcEndingDate := 0D;
        CurrentCalcBestUnitPrice := 0;

        // RESET STALE STAGING DATA: Purge staging records for this Shop at the start of a new sync run
        StagingRec.SetRange("Shop Code", Shop.Code);
        if not StagingRec.IsEmpty() then
            StagingRec.DeleteAll();

        LogDiag('FilterProducts:Start', '', Shop.Code, true, false, 0, 0D, '', StrSubstNo('SyncPrices=%1, ProductMetafieldsToShopify=%2, SessionId=%3', Shop."Sync Prices", Shop."Product Metafields To Shopify", SessionId()));

        ProductLoop.CopyFilters(ShopifyProduct);
        if ProductLoop.FindSet() then
            repeat
                if not IsNullGuid(ProductLoop."Item SystemId") then
                    if Item.GetBySystemId(ProductLoop."Item SystemId") then
                        if ProductTitleCU.IsItemApproved(Item) and (Item.Picture.Count() > 0) then begin
                            if FilterBuilder.Length() > 0 then
                                FilterBuilder.Append('|');
                            FilterBuilder.Append(Format(ProductLoop."Item SystemId", 0, 4));
                            ValidProductCount += 1;
                        end;
            until ProductLoop.Next() = 0;

        if ValidProductCount > 0 then
            ShopifyProduct.SetFilter("Item SystemId", FilterBuilder.ToText())
        else
            ShopifyProduct.SetRange("Item SystemId", CreateGuid()); // Block sync completely if no items pass approval and image gate
    end;

    // PRICING FIX: OVERRIDE CALCULATE UNIT PRICE WITH QUANTITY 1.0 TO CAPTURE SALES PRICE 123.45 & PREVENT UOM OVERWRITE
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnBeforeCalculateUnitPrice', '', false, false)]
    local procedure CalculateUnitPriceWithQuantityOne(
        Item: Record Item;
        VariantCode: Code[20];
        UnitOfMeasure: Code[20];
        ShopifyShop: Record "Shpfy Shop";
        Catalog: Record "Shpfy Catalog";
        var UnitCost: Decimal;
        var Price: Decimal;
        var ComparePrice: Decimal;
        var Handled: Boolean
    )
    var
        ShpfyUpdatePriceSource: Codeunit "Shpfy Update Price Source";
        CalcUnitCost: Decimal;
        CalcPrice: Decimal;
        CalcComparePrice: Decimal;
        CalcSucceeded: Boolean;
        PriceSourceBound: Boolean;
        ErrText: Text;
    begin
        if Handled then begin
            LogDiag('CalculateUnitPrice:AlreadyHandled', Item."No.", ShopifyShop.Code, true, false, Price, 0D, '', StrSubstNo('Handled was true on entry, SessionId=%1', SessionId()));
            exit;
        end;

        // Re-entrancy guard to prevent recursive calculation
        if IsCalculatingPrice then begin
            LogDiag('CalculateUnitPrice:Reentrant', Item."No.", ShopifyShop.Code, true, false, 0, 0D, '', StrSubstNo('IsCalculatingPrice was true, SessionId=%1', SessionId()));
            exit;
        end;

        IsCalculatingPrice := true;
        CurrentCalcItemNo := Item."No.";
        CurrentCalcShopCode := ShopifyShop.Code;
        CurrentCalcVariantCode := VariantCode;
        CurrentCalcEndingDate := 0D;
        CurrentCalcBestUnitPrice := 0;

        LogDiag('CalculateUnitPrice:Started', Item."No.", ShopifyShop.Code, true, false, 0, 0D, '', StrSubstNo('UOM=%1, Variant=%2, WorkDate=%3, Today=%4, SessionId=%5', UnitOfMeasure, VariantCode, WorkDate(), Today(), SessionId()));

        // Safely bind price source subscription
        BindSubscription(ShpfyUpdatePriceSource);
        PriceSourceBound := true;

        // Clear last error before invoking TryFunction to ensure clean diagnostic logging
        ClearLastError();

        // Execute price calculation protected by TryFunction
        CalcSucceeded := TryCalculatePrice(Item, VariantCode, UnitOfMeasure, ShopifyShop, Catalog, CalcUnitCost, CalcPrice, CalcComparePrice);

        // GUARANTEED UNBIND: Clean up subscription safely regardless of outcome
        if PriceSourceBound then
            UnbindSubscription(ShpfyUpdatePriceSource);

        // GUARANTEED RESET: Clear calculation guard and tracking state
        IsCalculatingPrice := false;

        // Assign outputs only if calculation succeeded; otherwise let Shopify Connector use default calculation
        if CalcSucceeded then begin
            UnitCost := CalcUnitCost;
            if CurrentCalcBestUnitPrice <> 0 then
                Price := CurrentCalcBestUnitPrice
            else
                Price := CalcPrice;
            ComparePrice := CalcComparePrice;
            Handled := true;

            // Record the ending date captured during this run into persistent staging table
            RecordEndingDateForVariant(Item."No.", ShopifyShop.Code, VariantCode, CurrentCalcEndingDate);

            LogDiag('CalculateUnitPrice:Success', Item."No.", ShopifyShop.Code, true, true, Price, CurrentCalcEndingDate, '', StrSubstNo('Cost=%1, Compare=%2, SessionId=%3', CalcUnitCost, CalcComparePrice, SessionId()));
        end else begin
            Handled := false;
            ErrText := GetLastErrorText();
            LogDiag('CalculateUnitPrice:TryFailed', Item."No.", ShopifyShop.Code, true, false, 0, 0D, ErrText, StrSubstNo('TryCalculatePrice returned false, SessionId=%1', SessionId()));
        end;

        CurrentCalcItemNo := '';
        CurrentCalcShopCode := '';
        CurrentCalcVariantCode := '';
        CurrentCalcBestUnitPrice := 0;
    end;

    [TryFunction]
    local procedure TryCalculatePrice(
        Item: Record Item;
        VariantCode: Code[20];
        UnitOfMeasure: Code[20];
        ShopifyShop: Record "Shpfy Shop";
        Catalog: Record "Shpfy Catalog";
        var CalcUnitCost: Decimal;
        var CalcPrice: Decimal;
        var CalcComparePrice: Decimal
    )
    var
        TempSalesHeader: Record "Sales Header" temporary;
        TempSalesLine: Record "Sales Line" temporary;
        Customer: Record Customer;
        CustomerNo: Code[20];
        CustomerPriceGroup: Code[10];
        CustomerDiscGroup: Code[20];
        AllowLineDisc: Boolean;
        GenBusPostingGroup: Code[20];
        VATBusPostingGroup: Code[20];
        TaxAreaCode: Code[20];
        TaxLiable: Boolean;
        VATCountryRegionCode: Code[10];
        CustomerPostingGroup: Code[20];
        CurrencyCode: Code[10];
        PricesIncludingVAT: Boolean;
    begin
        // Exactly matches Codeunit 30182 "Shpfy Product Price Calc." procedure SetParameters(SourceRec)
        if Catalog.Id <> 0 then begin
            GenBusPostingGroup := Catalog."Gen. Bus. Posting Group";
            VATBusPostingGroup := Catalog."VAT Bus. Posting Group";
            TaxAreaCode := Catalog."Tax Area Code";
            TaxLiable := Catalog."Tax Liable";
            VATCountryRegionCode := Catalog."VAT Country/Region Code";
            CustomerPriceGroup := Catalog."Customer Price Group";
            CustomerDiscGroup := Catalog."Customer Discount Group";
            CustomerPostingGroup := Catalog."Customer Posting Group";
            PricesIncludingVAT := Catalog."Prices Including VAT";
            AllowLineDisc := Catalog."Allow Line Disc.";
            CustomerNo := Catalog."Customer No.";
            CurrencyCode := Catalog."Currency Code";
        end else begin
            GenBusPostingGroup := ShopifyShop."Gen. Bus. Posting Group";
            VATBusPostingGroup := ShopifyShop."VAT Bus. Posting Group";
            TaxAreaCode := ShopifyShop."Tax Area Code";
            TaxLiable := ShopifyShop."Tax Liable";
            VATCountryRegionCode := ShopifyShop."VAT Country/Region Code";
            CustomerPriceGroup := ShopifyShop."Customer Price Group";
            CustomerDiscGroup := ShopifyShop."Customer Discount Group";
            CustomerPostingGroup := ShopifyShop."Customer Posting Group";
            PricesIncludingVAT := ShopifyShop."Prices Including VAT";
            AllowLineDisc := ShopifyShop."Allow Line Disc.";
            CurrencyCode := ShopifyShop."Currency Code";
        end;

        // Exactly matches Codeunit 30182 "Shpfy Product Price Calc." procedure CreateTempSalesHeader()
        Clear(TempSalesHeader);
        TempSalesHeader."Document Type" := TempSalesHeader."Document Type"::Quote;
        TempSalesHeader."No." := ShopifyShop.Code;

        if (CustomerNo <> '') and Customer.Get(CustomerNo) then begin
            TempSalesHeader."Sell-to Customer No." := CustomerNo;
            TempSalesHeader."Bill-to Customer No." := CustomerNo;
            TempSalesHeader."Customer Price Group" := Customer."Customer Price Group";
            TempSalesHeader."Customer Disc. Group" := Customer."Customer Disc. Group";
            TempSalesHeader."Allow Line Disc." := Customer."Allow Line Disc.";
        end else begin
            TempSalesHeader."Sell-to Customer No." := ShopifyShop.Code;
            TempSalesHeader."Bill-to Customer No." := ShopifyShop.Code;
            TempSalesHeader."Customer Price Group" := CustomerPriceGroup;
            TempSalesHeader."Customer Disc. Group" := CustomerDiscGroup;
            TempSalesHeader."Allow Line Disc." := AllowLineDisc;
        end;

        TempSalesHeader."Gen. Bus. Posting Group" := GenBusPostingGroup;
        TempSalesHeader."VAT Bus. Posting Group" := VATBusPostingGroup;
        TempSalesHeader."Tax Area Code" := TaxAreaCode;
        TempSalesHeader."Tax Liable" := TaxLiable;
        TempSalesHeader."VAT Country/Region Code" := VATCountryRegionCode;
        TempSalesHeader."Customer Posting Group" := CustomerPostingGroup;
        TempSalesHeader."Prices Including VAT" := PricesIncludingVAT;

        TempSalesHeader.Validate("Document Date", WorkDate());
        TempSalesHeader.Validate("Order Date", WorkDate());
        TempSalesHeader.Validate("Currency Code", CurrencyCode);
        TempSalesHeader.Insert(false);

        // Exactly matches Codeunit 30182 "Shpfy Product Price Calc." procedure CalcPrice()
        Clear(TempSalesLine);
        TempSalesLine."Document Type" := TempSalesHeader."Document Type";
        TempSalesLine."Document No." := TempSalesHeader."No.";
        TempSalesLine."System-Created Entry" := true;
        TempSalesLine.SetSalesHeader(TempSalesHeader);
        TempSalesLine.Validate(Type, TempSalesLine.Type::Item);
        TempSalesLine.Validate("No.", Item."No.");
        if VariantCode <> '' then
            TempSalesLine.Validate("Variant Code", VariantCode);

        // Key step: Set Quantity = 1.0 to trigger sales price minimum quantity evaluation
        TempSalesLine.Validate(Quantity, 1);

        if UnitOfMeasure <> '' then
            TempSalesLine.Validate("Unit of Measure Code", UnitOfMeasure);

        // Assign exactly matching Codeunit 30182 "Shpfy Product Price Calc." lines 78-80
        CalcUnitCost := TempSalesLine."Unit Cost";
        CalcComparePrice := TempSalesLine."Unit Price";
        CalcPrice := TempSalesLine."Line Amount";

        if CalcComparePrice <= CalcPrice then
            CalcComparePrice := 0;
    end;

    // PRICING FIX 1 (NEW PRICING EXPERIENCE): CAPTURE ENDING DATE FROM PRICE LIST LINE (V18+)
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales Line - Price", 'OnAfterSetPrice', '', false, false)]
    local procedure CaptureSalesPriceEndingDate(
        var SalesLine: Record "Sales Line";
        PriceListLine: Record "Price List Line";
        AmountType: Enum "Price Amount Type";
        var SalesHeader: Record "Sales Header"
    )
    begin
        if not IsCalculatingPrice then
            exit;

        if not SalesLine.IsTemporary() then
            exit;

        if SalesLine.Type <> SalesLine.Type::Item then
            exit;

        if SalesLine."No." <> CurrentCalcItemNo then
            exit;

        if (CurrentCalcVariantCode <> '') and (SalesLine."Variant Code" <> CurrentCalcVariantCode) then
            exit;

        LogDiag('CaptureSalesPriceEndingDate', SalesLine."No.", CurrentCalcShopCode, true, true, PriceListLine."Unit Price", PriceListLine."Ending Date", '', StrSubstNo('ListCode=%1, LineNo=%2, Start=%3, End=%4, SessionId=%5', PriceListLine."Price List Code", PriceListLine."Line No.", PriceListLine."Starting Date", PriceListLine."Ending Date", SessionId()));

        if PriceListLine."Unit Price" <> 0 then
            CurrentCalcBestUnitPrice := PriceListLine."Unit Price";

        if PriceListLine."Ending Date" <> 0D then
            CurrentCalcEndingDate := PriceListLine."Ending Date";
    end;

    // PRICING FIX 2 (LEGACY PRICING EXPERIENCE): CAPTURE ENDING DATE AND BEST PRICE FROM SALES PRICE (TABLE 7002 / CU 7000)
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales Price Calc. Mgt.", 'OnAfterCalcBestUnitPrice', '', false, false)]
    local procedure CaptureLegacyBestSalesPriceEndingDate(
        var SalesPrice: Record "Sales Price";
        var BestSalesPrice: Record "Sales Price";
        FoundSalesPrice: Boolean
    )
    begin
        if not IsCalculatingPrice then
            exit;

        if not FoundSalesPrice then
            exit;

        if BestSalesPrice."Item No." <> CurrentCalcItemNo then
            exit;

        LogDiag('CaptureLegacyBestSalesPrice', BestSalesPrice."Item No.", CurrentCalcShopCode, true, true, BestSalesPrice."Unit Price", BestSalesPrice."Ending Date", '', StrSubstNo('RawUnitPrice=%1, MinQty=%2, EndDate=%3, SessionId=%4', BestSalesPrice."Unit Price", BestSalesPrice."Minimum Quantity", BestSalesPrice."Ending Date", SessionId()));

        if BestSalesPrice."Unit Price" <> 0 then
            CurrentCalcBestUnitPrice := BestSalesPrice."Unit Price";

        if BestSalesPrice."Ending Date" <> 0D then
            CurrentCalcEndingDate := BestSalesPrice."Ending Date";
    end;

    local procedure RecordEndingDateForVariant(ItemNo: Code[20]; ShopCode: Code[20]; VariantCode: Code[20]; EndingDate: Date)
    var
        StagingRec: Record "APSS Item Price Ending Date";
    begin
        if (ItemNo = '') or (ShopCode = '') then
            exit;

        if StagingRec.Get(ItemNo, ShopCode) then begin
            // Reset conflict flag if record is from a previous NST session
            if StagingRec."Last Session ID" <> SessionId() then begin
                StagingRec."Has Variant Conflict" := false;
                StagingRec."Ending Date" := EndingDate;
                StagingRec."Last Updated" := CurrentDateTime;
                StagingRec."Last Session ID" := SessionId();
                StagingRec.Modify(true);
                exit;
            end;

            if StagingRec."Has Variant Conflict" then
                exit;

            if (StagingRec."Ending Date" <> 0D) and (StagingRec."Ending Date" <> EndingDate) then begin
                StagingRec."Has Variant Conflict" := true;
                StagingRec."Ending Date" := 0D;
                StagingRec."Last Updated" := CurrentDateTime;
                StagingRec."Last Session ID" := SessionId();
                StagingRec.Modify(true);
            end else begin
                StagingRec."Ending Date" := EndingDate;
                StagingRec."Last Updated" := CurrentDateTime;
                StagingRec."Last Session ID" := SessionId();
                StagingRec.Modify(true);
            end;
        end else begin
            Clear(StagingRec);
            StagingRec."Item No." := ItemNo;
            StagingRec."Shop Code" := ShopCode;
            StagingRec."Ending Date" := EndingDate;
            StagingRec."Has Variant Conflict" := false;
            StagingRec."Last Updated" := CurrentDateTime;
            StagingRec."Last Session ID" := SessionId();
            StagingRec.Insert(true);
        end;
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
        PriceEndingDateRec: Record "APSS Item Price Ending Date";
        ProductTitleCU: Codeunit "APSS Shopify Product Title";
        BrandName: Text;
        LeadTimeText: Text;
    begin
        if ShopifyProduct.Id = 0 then
            exit(false);

        if IsNullGuid(ShopifyProduct."Item SystemId") then
            exit(false);

        if not Item.GetBySystemId(ShopifyProduct."Item SystemId") then
            exit(false);

        LogDiag('PopulateMetafield:Start', Item."No.", ShopifyProduct."Shop Code", true, true, 0, 0D, '', StrSubstNo('ProductId=%1, SessionId=%2', ShopifyProduct.Id, SessionId()));

        // brand
        BrandName := ProductTitleCU.GetBrandName(Item);
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'brand', BrandName, Enum::"Shpfy Metafield Type"::single_line_text_field);

        // manufacture_number (Customer Item Reference No.)
        SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'manufacture_number', ProductTitleCU.GetCustomerItemReference(Item), Enum::"Shpfy Metafield Type"::single_line_text_field);

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

        // price_valid_until (Date format: YYYY-MM-DD)
        if PriceEndingDateRec.Get(Item."No.", ShopifyProduct."Shop Code") then begin
            if PriceEndingDateRec."Has Variant Conflict" then
                LogDiag('PopulateMetafield:ConflictDeferred', Item."No.", ShopifyProduct."Shop Code", true, false, 0, 0D, '', StrSubstNo('Variant ending date conflict detected in staging DB, SessionId=%1', SessionId()))
            else if PriceEndingDateRec."Ending Date" <> 0D then begin
                SetOrUpdateMetafield(ShopifyProduct.Id, 'custom', 'price_valid_until', Format(PriceEndingDateRec."Ending Date", 0, '<Year4>-<Month,2>-<Day,2>'), Enum::"Shpfy Metafield Type"::date);
                LogDiag('PopulateMetafield:PriceValidUntilSet', Item."No.", ShopifyProduct."Shop Code", true, true, 0, PriceEndingDateRec."Ending Date", '', StrSubstNo('Value=%1, SessionId=%2', Format(PriceEndingDateRec."Ending Date", 0, '<Year4>-<Month,2>-<Day,2>'), SessionId()));
            end else
                LogDiag('PopulateMetafield:EndingDateZero', Item."No.", ShopifyProduct."Shop Code", true, false, 0, 0D, '', StrSubstNo('Staging DB ending date is 0D, SessionId=%1', SessionId()));
        end else
            LogDiag('PopulateMetafield:NoStagingRecord', Item."No.", ShopifyProduct."Shop Code", true, false, 0, 0D, '', StrSubstNo('No APSS Item Price Ending Date record found in DB, SessionId=%1', SessionId()));

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
        if OwnerId = 0 then
            exit;

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
                LogDiag('SetMetafield:Modify', Format(OwnerId), '', true, true, 0, 0D, '', StrSubstNo('%1.%2=%3, SessionId=%4', MetafieldNamespace, MetafieldName, MetafieldValue, SessionId()));
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
            LogDiag('SetMetafield:Insert', Format(OwnerId), '', true, true, 0, 0D, '', StrSubstNo('%1.%2=%3, SessionId=%4', MetafieldNamespace, MetafieldName, MetafieldValue, SessionId()));
        end;
    end;
}
