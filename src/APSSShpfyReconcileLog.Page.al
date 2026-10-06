namespace APSS.Shopify;

using Microsoft.Integration.Shopify;

page 90303 "APSS Shpfy Reconcile Log"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "APSS Shpfy Reconcile Log";
    Caption = 'Shopify Reconcile Log';
    Editable = true;
    InsertAllowed = false;
    DeleteAllowed = true;
    ModifyAllowed = true;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(Selected; Rec.Selected)
                {
                    ApplicationArea = All;
                    Caption = 'Select';
                    Editable = true;
                    ToolTip = 'Specifies whether this log entry is selected for resolution.';
                }
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the unique log entry number.';
                }
                field("Logged At"; Rec."Logged At")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the timestamp when the entry was logged.';
                }
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Business Central Item No.';
                }
                field("Variant Code"; Rec."Variant Code")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Business Central Variant Code.';
                }
                field(SKU; Rec.SKU)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Shopify Variant SKU.';
                }
                field("Shopify Product Id"; Rec."Shopify Product Id")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Product Id on Shopify.';
                }
                field("Shopify Variant Id"; Rec."Shopify Variant Id")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Variant Id on Shopify.';
                }
                field("Shopify Handle"; Rec."Shopify Handle")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Product Handle on Shopify.';
                }
                field("Shopify Status"; Rec."Shopify Status")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the Product Status on Shopify.';
                }
                field(Reason; Rec.Reason)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the reason for blocking/reconciliation.';
                }
                field(Details; Rec.Details)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies diagnostic details.';
                }
                field(Resolved; Rec.Resolved)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies whether the issue has been resolved.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SelectAll)
            {
                ApplicationArea = All;
                Caption = 'Select All';
                Image = CheckList;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Selects all log entries in the current view.';

                trigger OnAction()
                var
                    LogRec: Record "APSS Shpfy Reconcile Log";
                begin
                    LogRec.Copy(Rec);
                    if LogRec.FindSet(true) then
                        repeat
                            LogRec.Selected := true;
                            LogRec.Modify(false);
                        until LogRec.Next() = 0;
                    CurrPage.Update(false);
                end;
            }
            action(DeselectAll)
            {
                ApplicationArea = All;
                Caption = 'Deselect All';
                Image = Cancel;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Deselects all log entries.';

                trigger OnAction()
                var
                    LogRec: Record "APSS Shpfy Reconcile Log";
                begin
                    LogRec.Copy(Rec);
                    if LogRec.FindSet(true) then
                        repeat
                            LogRec.Selected := false;
                            LogRec.Modify(false);
                        until LogRec.Next() = 0;
                    CurrPage.Update(false);
                end;
            }
            action(ApplyMappingsFromLog)
            {
                ApplicationArea = All;
                Caption = 'Apply Mappings from Log';
                Image = Link;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Applies validated Shopify Product ID and Variant mappings for selected log entries without downloading unmapped store catalog items.';

                trigger OnAction()
                var
                    SelectedLog: Record "APSS Shpfy Reconcile Log";
                    SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
                    SuccessCount: Integer;
                    FailedCount: Integer;
                begin
                    SelectedLog.SetRange(Selected, true);
                    if SelectedLog.IsEmpty() then
                        CurrPage.SetSelectionFilter(SelectedLog);

                    if SelectedLog.IsEmpty() then begin
                        Message('Please select at least one log entry to apply mapping.');
                        exit;
                    end;

                    SKUPrecheck.ApplyMappingsFromReconcileLog(SelectedLog, SuccessCount, FailedCount);
                    Message('Mapping applied: %1 succeeded, %2 skipped/failed.', SuccessCount, FailedCount);
                    CurrPage.Update(false);
                end;
            }
            action(MarkAsResolved)
            {
                ApplicationArea = All;
                Caption = 'Mark as Resolved';
                Image = Approve;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Marks selected log entries as resolved.';

                trigger OnAction()
                var
                    SelectedLog: Record "APSS Shpfy Reconcile Log";
                    ResolvedCount: Integer;
                begin
                    // 1. Check entries with Selected checkbox = true
                    SelectedLog.SetRange(Selected, true);
                    if SelectedLog.FindSet(true) then begin
                        repeat
                            SelectedLog.Resolved := true;
                            SelectedLog.Selected := false;
                            SelectedLog.Modify(false);
                            ResolvedCount += 1;
                        until SelectedLog.Next() = 0;
                    end else begin
                        // 2. Fallback to row selection filter
                        CurrPage.SetSelectionFilter(SelectedLog);
                        if SelectedLog.FindSet(true) then
                            repeat
                                SelectedLog.Resolved := true;
                                SelectedLog.Selected := false;
                                SelectedLog.Modify(false);
                                ResolvedCount += 1;
                            until SelectedLog.Next() = 0;
                    end;

                    if ResolvedCount > 0 then begin
                        Message('%1 log entry(ies) have been marked as resolved.', ResolvedCount);
                        CurrPage.Update(false);
                    end else
                        Message('Please select at least one log entry to resolve.');
                end;
            }
            action(MarkAllAsResolved)
            {
                ApplicationArea = All;
                Caption = 'Mark ALL as Resolved';
                Image = CompleteLine;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Marks ALL unresolved log entries in the system as resolved.';

                trigger OnAction()
                var
                    UnresolvedLog: Record "APSS Shpfy Reconcile Log";
                    TotalCount: Integer;
                begin
                    UnresolvedLog.SetRange(Resolved, false);
                    TotalCount := UnresolvedLog.Count();
                    if TotalCount = 0 then begin
                        Message('There are no unresolved log entries.');
                        exit;
                    end;

                    if Confirm('Do you want to mark all %1 unresolved log entries as resolved?', true, TotalCount) then begin
                        UnresolvedLog.ModifyAll(Resolved, true, false);
                        UnresolvedLog.ModifyAll(Selected, false, false);
                        Message('All %1 log entries have been marked as resolved.', TotalCount);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(DeleteSelected)
            {
                ApplicationArea = All;
                Caption = 'Delete Selected';
                Image = Delete;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Permanently deletes all selected log entries.';

                trigger OnAction()
                var
                    SelectedLog: Record "APSS Shpfy Reconcile Log";
                    DeleteCount: Integer;
                begin
                    // 1. Check entries with Selected checkbox = true
                    SelectedLog.SetRange(Selected, true);
                    DeleteCount := SelectedLog.Count();
                    if DeleteCount > 0 then begin
                        if Confirm('Are you sure you want to permanently delete %1 selected log entry(ies)?', true, DeleteCount) then begin
                            SelectedLog.DeleteAll(true);
                            Message('%1 log entry(ies) have been deleted.', DeleteCount);
                            CurrPage.Update(false);
                        end;
                        exit;
                    end;

                    // 2. Fallback to row selection filter
                    CurrPage.SetSelectionFilter(SelectedLog);
                    DeleteCount := SelectedLog.Count();
                    if DeleteCount > 0 then begin
                        if Confirm('Are you sure you want to permanently delete %1 selected log entry(ies)?', true, DeleteCount) then begin
                            SelectedLog.DeleteAll(true);
                            Message('%1 log entry(ies) have been deleted.', DeleteCount);
                            CurrPage.Update(false);
                        end;
                    end else
                        Message('Please select at least one log entry to delete.');
                end;
            }
            action(PurgeIncompleteRecords)
            {
                ApplicationArea = All;
                Caption = 'Purge Incomplete Records (Id = 0)';
                Image = Delete;
                Promoted = true;
                PromotedCategory = Process;
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
            action(ScanOrphanedMappings)
            {
                ApplicationArea = All;
                Caption = 'Scan Orphaned Shopify Mappings';
                Image = Find;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Scans BC Shopify Products for IDs that no longer exist on Shopify Admin. Findings are logged without deleting records.';

                trigger OnAction()
                var
                    Shop: Record "Shpfy Shop";
                    SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
                    OrphanCount: Integer;
                begin
                    if Shop.FindFirst() then begin
                        SKUPrecheck.ScanOrphanedMappings(Shop.Code, OrphanCount);
                        Message('Scan completed for Shop %1. %2 orphaned mapping(s) found and logged.', Shop.Code, OrphanCount);
                        CurrPage.Update(false);
                    end else
                        Error('No Shopify Shop found.');
                end;
            }
        }
    }
}
