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
                    ShpfyProduct: Record "Shpfy Product";
                    ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
                    SyncEvents: Codeunit "APSS Shopify Sync Events";
                    ItemSelectionPage: Page "APSS Shopify Item Selection";
                    Status: Enum "APSS Shopify Item Sync Status";
                    NewFilterBuilder: TextBuilder;
                    ModifiedFilterBuilder: TextBuilder;
                    ParametersXml: Text;
                    ValidCount: Integer;
                    NewCount: Integer;
                    ModifiedCount: Integer;
                    ReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Add Item to Shopify" id="30106"><Options><Field name="ShopCode">%1</Field><Field name="SyncImages">true</Field><Field name="SyncInventory">true</Field></Options><DataItems><DataItem name="Item">%2</DataItem></DataItems></ReportParameters>', Locked = true;
                    SyncProductsReportParametersTxt: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="Shpfy Sync Products" id="30108"><Options><Field name="OnlySyncPrices">false</Field></Options><DataItems><DataItem name="Shop">VERSION(1) SORTING(Code) WHERE(Code=1(%1))</DataItem></DataItems></ReportParameters>', Locked = true;
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
                            NewCount := 0;
                            ModifiedCount := 0;
                            Clear(NewFilterBuilder);
                            Clear(ModifiedFilterBuilder);
                            repeat
                                Status := ShopifyReadinessMgt.GetItemSyncStatus(SelectedItem);
                                if Status = Enum::"APSS Shopify Item Sync Status"::"New Ready" then begin
                                    NewCount += 1;
                                    if NewFilterBuilder.Length() > 0 then
                                        NewFilterBuilder.Append('|');
                                    NewFilterBuilder.Append('''' + SelectedItem."No." + '''');
                                end else if Status = Enum::"APSS Shopify Item Sync Status"::"Modified Ready" then begin
                                    ModifiedCount += 1;
                                    if ModifiedFilterBuilder.Length() > 0 then
                                        ModifiedFilterBuilder.Append('|');
                                    ModifiedFilterBuilder.Append(Format(SelectedItem.SystemId, 0, 4));
                                end;
                            until SelectedItem.Next() = 0;

                            if (NewCount > 0) or (ModifiedCount > 0) then begin
                                if not ShopifyShop.FindFirst() then
                                    Error('No Shopify Shop found. Please configure a Shopify Shop first.');

                                // 1. Process New Ready Items through Add Item Report
                                if NewCount > 0 then begin
                                    FilterNewItem.SetFilter("No.", NewFilterBuilder.ToText());
                                    ParametersXml := StrSubstNo(ReportParametersTxt, ShopifyShop.Code, FilterNewItem.GetView(false));
                                    Report.Execute(Report::"Shpfy Add Item to Shopify", ParametersXml);
                                end;

                                // 2. Process Modified Ready Items through Sync Products Report with targeted SystemId filter
                                if ModifiedCount > 0 then begin
                                    SyncEvents.SetSelectedModifiedItemFilter(ModifiedFilterBuilder.ToText());
                                    ParametersXml := StrSubstNo(SyncProductsReportParametersTxt, ShopifyShop.Code);
                                    Report.Execute(Report::"Shpfy Sync Products", ParametersXml);
                                    SyncEvents.ClearSelectedModifiedItemFilter();
                                end;

                                CurrPage.Update(false);

                                Message('%1 new item(s) and %2 modified item(s) were processed for Shopify sync.', NewCount, ModifiedCount);
                            end;
                        end;
                    end;
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
}
