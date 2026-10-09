namespace APSS.Shopify;

using Microsoft.Integration.Shopify;
using Microsoft.Inventory.Item;
using System.Threading;

codeunit 90306 "APSS Shopify Auto Sync Job"
{
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        ShopCode: Code[20];
    begin
        ShopCode := CopyStr(Rec."Parameter String", 1, MaxStrLen(ShopCode));
        RunAutoSync(ShopCode);
    end;

    procedure RunAutoSync(TargetShopCode: Code[20])
    var
        ShopifyShop: Record "Shpfy Shop";
        CandidateItem: Record Item;
        ReadyItem: Record Item temporary;
        FilterNewItem: Record Item;
        ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
        SyncEvents: Codeunit "APSS Shopify Sync Events";
        EmailMgt: Codeunit "APSS Shopify Email Mgt.";
        SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
        Status: Enum "APSS Shopify Item Sync Status";
        SyncAction: Enum "APSS Shpfy Sync Action";
        NewFilterBuilder: TextBuilder;
        ModifiedFilterBuilder: TextBuilder;
        BatchSKUsList: List of [Text];
        ReasonText: Text;
        ParametersXml: Text;
        NewCount: Integer;
        ModifiedCount: Integer;
        SkippedSKUCount: Integer;
        ErrText: Text;
        ReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Add Item to Shopify" id="30106"><Options><Field name="ShopCode">%1</Field><Field name="SyncImages">false</Field><Field name="SyncInventory">true</Field></Options><DataItems><DataItem name="Item">%2</DataItem></DataItems></ReportParameters>', Locked = true;
        SyncProductsReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Sync Products" id="30108"><Options><Field name="OnlySyncPrices">false</Field></Options><DataItems><DataItem name="Shop">VERSION(1) SORTING(Code) WHERE(Code=1(%1))</DataItem></DataItems></ReportParameters>', Locked = true;
        SyncImagesReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Sync Images" id="30107"><DataItems><DataItem name="Shop">VERSION(1) SORTING(Code) WHERE(Code=1(%1))</DataItem></DataItems></ReportParameters>', Locked = true;
    begin
        if TargetShopCode <> '' then begin
            if not ShopifyShop.Get(TargetShopCode) then
                Error('Shopify Shop %1 configured in Job Queue parameters was not found.', TargetShopCode);
        end else if not ShopifyShop.FindFirst() then
            Error('No Shopify Shop found. Please configure a Shopify Shop before running Auto Sync.');

        if SKUPrecheck.IsPrecheckEnabled(ShopifyShop.Code) then
            if (SKUPrecheck.GetShopifyAccessToken(ShopifyShop.Code) = '') or (SKUPrecheck.GetShopUrl(ShopifyShop) = '') then
                Error('Shopify SKU Precheck is enabled, but Shopify credentials are not configured on Shopify Shop %1.', ShopifyShop.Code);

        // 1. Refresh item readiness across all items
        ShopifyReadinessMgt.RefreshAllItems();
        Commit();

        // 2. Scan and collect all New Ready and Modified Ready items
        CandidateItem.Reset();
        ReadyItem.Reset();
        ReadyItem.DeleteAll();

        if CandidateItem.FindSet() then
            repeat
                Status := ShopifyReadinessMgt.GetItemSyncStatus(CandidateItem);
                if (Status = Enum::"APSS Shopify Item Sync Status"::"New Ready") or (Status = Enum::"APSS Shopify Item Sync Status"::"Modified Ready") then begin
                    ReadyItem := CandidateItem;
                    ReadyItem.Insert();
                end;
            until CandidateItem.Next() = 0;

        if ReadyItem.IsEmpty() then begin
            LogDiag('AutoSync:NoReadyItems', '', ShopifyShop.Code, true, true, 0, 0D, '', 'Auto sync scanned inventory: 0 items in New Ready or Modified Ready status.');
            exit;
        end;

        NewCount := 0;
        ModifiedCount := 0;
        SkippedSKUCount := 0;
        Clear(NewFilterBuilder);
        Clear(ModifiedFilterBuilder);
        Clear(BatchSKUsList);

        if ReadyItem.FindSet() then
            repeat
                SKUPrecheck.SanitizeItemMarketingText(ReadyItem);
                if SKUPrecheck.EvaluateItemSyncEligibility(ShopifyShop.Code, ReadyItem, BatchSKUsList, SyncAction, ReasonText) then begin
                    case SyncAction of
                        SyncAction::Create:
                            begin
                                NewCount += 1;
                                if NewFilterBuilder.Length() > 0 then
                                    NewFilterBuilder.Append('|');
                                NewFilterBuilder.Append('''' + ReadyItem."No." + '''');
                            end;
                        SyncAction::Update:
                            begin
                                ModifiedCount += 1;
                                if ModifiedFilterBuilder.Length() > 0 then
                                    ModifiedFilterBuilder.Append('|');
                                ModifiedFilterBuilder.Append(Format(ReadyItem.SystemId, 0, 4));
                            end;
                    end;
                end else
                    SkippedSKUCount += 1;
            until ReadyItem.Next() = 0;

        if (NewCount = 0) and (ModifiedCount = 0) then begin
            LogDiag('AutoSync:AllSkipped', '', ShopifyShop.Code, true, true, 0, 0D, '', StrSubstNo('All %1 candidate item(s) skipped due to SKU Precheck/Reconcile conflicts.', SkippedSKUCount));
            exit;
        end;

        // 3. Process New Ready Items through Add Item Report (30106)
        if NewCount > 0 then begin
            FilterNewItem.SetFilter("No.", NewFilterBuilder.ToText());
            ParametersXml := StrSubstNo(ReportParametersTxt, ShopifyShop.Code, FilterNewItem.GetView(false));
            if not TryExecuteAddItemReport(ParametersXml) then begin
                ErrText := GetLastErrorText();
                EmailMgt.SendErrorNotification(ShopifyShop.Code, ReadyItem, 'Shopify Auto Sync Add Item Failure', ErrText);
                LogDiag('AutoSync:AddItemFailed', '', ShopifyShop.Code, true, false, 0, 0D, ErrText, StrSubstNo('Failed adding %1 new item(s).', NewCount));
                Error('Shopify Auto Sync Add Item Failure: %1', ErrText);
            end;
        end;

        // 4. Process Modified Ready Items through Sync Products Report (30108) with targeted SystemId filter
        if ModifiedCount > 0 then begin
            SyncEvents.SetSelectedModifiedItemFilter(ModifiedFilterBuilder.ToText());
            ParametersXml := StrSubstNo(SyncProductsReportParametersTxt, ShopifyShop.Code);
            Commit();
            if not TryExecuteSyncProductsReport(ParametersXml) then begin
                SyncEvents.ClearSelectedModifiedItemFilter();
                ErrText := GetLastErrorText();
                EmailMgt.SendErrorNotification(ShopifyShop.Code, ReadyItem, 'Shopify Auto Sync Product Update Failure', ErrText);
                LogDiag('AutoSync:SyncProductsFailed', '', ShopifyShop.Code, true, false, 0, 0D, ErrText, StrSubstNo('Failed updating %1 modified item(s).', ModifiedCount));
                Error('Shopify Auto Sync Product Update Failure: %1', ErrText);
            end;
            SyncEvents.ClearSelectedModifiedItemFilter();
        end;

        // 5. Process Product Images through Sync Images Report (30107)
        ParametersXml := StrSubstNo(SyncImagesReportParametersTxt, ShopifyShop.Code);
        Commit();
        if not TryExecuteSyncImagesReport(ParametersXml) then begin
            ErrText := GetLastErrorText();
            EmailMgt.SendErrorNotification(ShopifyShop.Code, ReadyItem, 'Shopify Auto Sync Image Failure', ErrText);
            LogDiag('AutoSync:SyncImagesFailed', '', ShopifyShop.Code, true, false, 0, 0D, ErrText, 'Failed syncing product images.');
            Error('Shopify Auto Sync Image Failure: %1', ErrText);
        end;

        // 6. Send HTML summary email to Procurement & Log Success
        EmailMgt.SendSyncNotification(ShopifyShop.Code, ReadyItem, NewCount, ModifiedCount);
        LogDiag('AutoSync:Success', '', ShopifyShop.Code, true, true, 0, 0D, '', StrSubstNo('Successfully auto-synced %1 new item(s) and %2 modified item(s). %3 skipped.', NewCount, ModifiedCount, SkippedSKUCount));
    end;

    [TryFunction]
    local procedure TryExecuteAddItemReport(ParametersXml: Text)
    begin
        Report.Execute(Report::"Shpfy Add Item to Shopify", ParametersXml);
    end;

    [TryFunction]
    local procedure TryExecuteSyncProductsReport(ParametersXml: Text)
    begin
        Report.Execute(Report::"Shpfy Sync Products", ParametersXml);
    end;

    [TryFunction]
    local procedure TryExecuteSyncImagesReport(ParametersXml: Text)
    begin
        Report.Execute(Report::"Shpfy Sync Images", ParametersXml);
    end;

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
}
