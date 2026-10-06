pageextension 90300 "APSS Item List Shopify" extends "Item List"
{
    layout
    {
        addafter(Description)
        {
            field("APSS Has Shopify Image"; Rec."APSS Has Shopify Image")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies whether the item has a Business Central item picture for Shopify.';
            }
            field("APSS Shopify Ready"; Rec."APSS Shopify Ready")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies whether the item has the minimum information required for Shopify.';
            }
            field("APSS Shopify Validation"; Rec."APSS Shopify Validation")
            {
                ApplicationArea = All;
                ToolTip = 'Shows the information that must be completed before the item is exported to Shopify.';
            }
            field("APSS Shopify Sync Status"; SyncStatus)
            {
                ApplicationArea = All;
                Caption = 'Shopify Sync Status';
                ToolTip = 'Shows the sync status: New Ready (Strong/Bold), Modified Ready (Attention/Amber), Synced Unchanged (Subordinate), or Not Ready.';
                StyleExpr = SyncStatusStyle;
            }
        }
        addfirst(factboxes)
        {
            part(ShopifyReadinessFactBox; "APSS Shpfy Readiness FactBox")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        addlast(Processing)
        {

            action("Refresh Selected Shopify Readiness")
            {
                ApplicationArea = All;
                Caption = 'Refresh Selected Shopify Readiness';
                Image = Refresh;
                ToolTip = 'Checks Shopify readiness for the selected item lines.';

                trigger OnAction()
                var
                    SelectedItem: Record Item;
                    ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
                begin
                    CurrPage.SetSelectionFilter(SelectedItem);
                    ShopifyReadinessMgt.RefreshSelectedItems(SelectedItem);
                    CurrPage.Update(false);
                end;
            }
            action("Refresh All Shopify Readiness")
            {
                ApplicationArea = All;
                Caption = 'Refresh All Shopify Readiness';
                Image = RefreshLines;
                ToolTip = 'Checks Shopify readiness for all items.';

                trigger OnAction()
                var
                    ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
                begin
                    ShopifyReadinessMgt.RefreshAllItems();
                    CurrPage.Update(false);
                end;
            }
            action("Add Ready Items to Shopify")
            {
                ApplicationArea = All;
                Caption = 'Add Ready Items to Shopify';
                Image = Export;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Displays a popup of all items meeting readiness criteria (New Ready or Modified Ready), allowing you to select which items to export to Shopify.';

                trigger OnAction()
                var
                    CandidateItem: Record Item;
                    ReadyItem: Record Item temporary;
                    SelectedItem: Record Item temporary;
                    FilterNewItem: Record Item;
                    ShopifyShop: Record "Shpfy Shop";
                    ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
                    SyncEvents: Codeunit "APSS Shopify Sync Events";
                    EmailMgt: Codeunit "APSS Shopify Email Mgt.";
                    SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
                    ItemSelectionPage: Page "APSS Shopify Item Selection";
                    Status: Enum "APSS Shopify Item Sync Status";
                    SyncAction: Enum "APSS Shpfy Sync Action";
                    NewFilterBuilder: TextBuilder;
                    ModifiedFilterBuilder: TextBuilder;
                    BatchSKUsList: List of [Text];
                    ReasonText: Text;
                    ParametersXml: Text;
                    ValidCount: Integer;
                    NewCount: Integer;
                    ModifiedCount: Integer;
                    SkippedSKUCount: Integer;
                    ReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Add Item to Shopify" id="30106"><Options><Field name="ShopCode">%1</Field><Field name="SyncImages">false</Field><Field name="SyncInventory">true</Field></Options><DataItems><DataItem name="Item">%2</DataItem></DataItems></ReportParameters>', Locked = true;
                    SyncProductsReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Sync Products" id="30108"><Options><Field name="OnlySyncPrices">false</Field></Options><DataItems><DataItem name="Shop">VERSION(1) SORTING(Code) WHERE(Code=1(%1))</DataItem></DataItems></ReportParameters>', Locked = true;
                    SyncImagesReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Sync Images" id="30107"><DataItems><DataItem name="Shop">VERSION(1) SORTING(Code) WHERE(Code=1(%1))</DataItem></DataItems></ReportParameters>', Locked = true;
                begin
                    CandidateItem.Reset();
                    ReadyItem.Reset();
                    ReadyItem.DeleteAll();

                    if CandidateItem.FindSet() then
                        repeat
                            Status := ShopifyReadinessMgt.GetItemSyncStatus(CandidateItem);
                            if (Status = Enum::"APSS Shopify Item Sync Status"::"New Ready") or (Status = Enum::"APSS Shopify Item Sync Status"::"Modified Ready") then begin
                                ReadyItem := CandidateItem;
                                ReadyItem.Insert();
                                ValidCount += 1;
                            end;
                        until CandidateItem.Next() = 0;

                    if ValidCount = 0 then begin
                        Message('No new or modified items meet the Shopify readiness criteria.');
                        exit;
                    end;

                    Clear(ItemSelectionPage);
                    ItemSelectionPage.SetItems(ReadyItem);
                    ItemSelectionPage.LookupMode(true);

                    if ItemSelectionPage.RunModal() = Action::LookupOK then begin
                        ItemSelectionPage.GetSelectedItems(SelectedItem);
                        if SelectedItem.FindSet() then begin
                            if not ShopifyShop.FindFirst() then
                                Error('No Shopify Shop found. Please configure a Shopify Shop first.');

                            if SKUPrecheck.IsPrecheckEnabled(ShopifyShop.Code) then
                                if (SKUPrecheck.GetShopifyAccessToken(ShopifyShop.Code) = '') or (SKUPrecheck.GetShopUrl(ShopifyShop) = '') then
                                    Error('Shopify SKU Precheck is enabled, but Shopify credentials are not configured on Shopify Shop %1.\\Please configure "APSS Shopify URL" and "Client ID / Client Secret" (or manual Token) on the Shopify Shop Card before exporting.', ShopifyShop.Code);

                            NewCount := 0;
                            ModifiedCount := 0;
                            SkippedSKUCount := 0;
                            Clear(NewFilterBuilder);
                            Clear(ModifiedFilterBuilder);
                            Clear(BatchSKUsList);

                            repeat
                                if SKUPrecheck.EvaluateItemSyncEligibility(ShopifyShop.Code, SelectedItem, BatchSKUsList, SyncAction, ReasonText) then begin
                                    case SyncAction of
                                        SyncAction::Create:
                                            begin
                                                NewCount += 1;
                                                if NewFilterBuilder.Length() > 0 then
                                                    NewFilterBuilder.Append('|');
                                                NewFilterBuilder.Append('''' + SelectedItem."No." + '''');
                                            end;
                                        SyncAction::Update:
                                            begin
                                                ModifiedCount += 1;
                                                if ModifiedFilterBuilder.Length() > 0 then
                                                    ModifiedFilterBuilder.Append('|');
                                                ModifiedFilterBuilder.Append(Format(SelectedItem.SystemId, 0, 4));
                                            end;
                                    end;
                                end else
                                    SkippedSKUCount += 1;
                            until SelectedItem.Next() = 0;

                            if (NewCount > 0) or (ModifiedCount > 0) then begin
                                // 1. Process New Ready Items through Add Item Report
                                if NewCount > 0 then begin
                                    FilterNewItem.SetFilter("No.", NewFilterBuilder.ToText());
                                    ParametersXml := StrSubstNo(ReportParametersTxt, ShopifyShop.Code, FilterNewItem.GetView(false));
                                    if not TryExecuteAddItemReport(ParametersXml) then begin
                                        EmailMgt.SendErrorNotification(
                                            ShopifyShop.Code,
                                            SelectedItem,
                                            'Shopify Add Item Sync Failure',
                                            GetLastErrorText()
                                        );
                                        Error(GetLastErrorText());
                                    end;
                                end;

                                // 2. Process Modified Ready Items through Sync Products Report with targeted SystemId filter
                                if ModifiedCount > 0 then begin
                                    SyncEvents.SetSelectedModifiedItemFilter(ModifiedFilterBuilder.ToText());
                                    ParametersXml := StrSubstNo(SyncProductsReportParametersTxt, ShopifyShop.Code);
                                    Commit();
                                    if not TryExecuteSyncProductsReport(ParametersXml) then begin
                                        SyncEvents.ClearSelectedModifiedItemFilter();
                                        EmailMgt.SendErrorNotification(
                                            ShopifyShop.Code,
                                            SelectedItem,
                                            'Shopify Product Sync Failure',
                                            GetLastErrorText()
                                        );
                                        Error(GetLastErrorText());
                                    end;
                                    SyncEvents.ClearSelectedModifiedItemFilter();
                                end;

                                // 3. Process Product Images through Sync Images Report
                                ParametersXml := StrSubstNo(SyncImagesReportParametersTxt, ShopifyShop.Code);
                                Commit();
                                if not TryExecuteSyncImagesReport(ParametersXml) then begin
                                    EmailMgt.SendErrorNotification(
                                        ShopifyShop.Code,
                                        SelectedItem,
                                        'Shopify Image Sync Failure',
                                        GetLastErrorText()
                                    );
                                    Error(GetLastErrorText());
                                end;

                                CurrPage.Update(false);

                                EmailMgt.SendSyncNotification(ShopifyShop.Code, SelectedItem, NewCount, ModifiedCount);

                                if SkippedSKUCount > 0 then
                                    Message('%1 new item(s) and %2 modified item(s) were processed. %3 item(s) were skipped due to SKU conflict/duplicate (see Shopify Reconcile Log).', NewCount, ModifiedCount, SkippedSKUCount);
                            end else if SkippedSKUCount > 0 then
                                Message('All %1 selected new item(s) were skipped due to SKU conflicts or duplicates. See Shopify Reconcile Log for details.', SkippedSKUCount);
                        end;
                    end;
                end;
            }
            action("Shopify Reconcile Log")
            {
                ApplicationArea = All;
                Caption = 'Shopify Reconcile Log';
                Image = Log;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                RunObject = Page "APSS Shpfy Reconcile Log";
                ToolTip = 'Opens the Shopify Reconcile Log showing blocked SKU exports and orphaned mappings.';
            }
            action("Purge Incomplete Shopify Records")
            {
                ApplicationArea = All;
                Caption = 'Purge Incomplete Shopify Records (Id = 0)';
                Image = Delete;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;
                ToolTip = 'Deletes all unmapped/incomplete Shopify Product and Variant records (Id = 0) left by failed sync attempts.';

                trigger OnAction()
                var
                    SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
                begin
                    if Confirm('Do you want to purge all incomplete/ghost Shopify Product and Variant records (Id = 0)?', true) then begin
                        SKUPrecheck.PurgeIncompleteRecords('');
                        Message('Incomplete records (Id = 0) have been purged.');
                        CurrPage.Update(false);
                    end;
                end;
            }
            action("Scan Orphaned Shopify Mappings")
            {
                ApplicationArea = All;
                Caption = 'Scan Orphaned Shopify Mappings';
                Image = Find;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;
                ToolTip = 'Scans BC Shopify Products for IDs that no longer exist on Shopify Admin. Findings are logged without deleting records.';

                trigger OnAction()
                var
                    Shop: Record "Shpfy Shop";
                    SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
                    OrphanCount: Integer;
                begin
                    if Shop.FindFirst() then begin
                        SKUPrecheck.ScanOrphanedMappings(Shop.Code, OrphanCount);
                        Message('Scan completed for Shop %1. %2 orphaned mapping(s) found and logged in Shopify Reconcile Log.', Shop.Code, OrphanCount);
                        Page.Run(Page::"APSS Shpfy Reconcile Log");
                    end else
                        Error('No Shopify Shop found.');
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
    begin
        SyncStatus := ShopifyReadinessMgt.GetItemSyncStatus(Rec);
        SyncStatusStyle := ShopifyReadinessMgt.GetSyncStatusStyle(Rec);
    end;

    var
        SyncStatus: Enum "APSS Shopify Item Sync Status";
        SyncStatusStyle: Text;

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
}
