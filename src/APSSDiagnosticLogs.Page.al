namespace Microsoft.Integration.Shopify;

page 90305 "APSS Diagnostic Logs"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "APSS Diagnostic Log";
    Caption = 'APSS Diagnostic Logs';
    Editable = false;
    SourceTableView = sorting("Entry No.") order(descending);

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                }
                field("Date Time"; Rec."Date Time")
                {
                    ApplicationArea = All;
                }
                field("Session ID"; Rec."Session ID")
                {
                    ApplicationArea = All;
                }
                field(Context; Rec.Context)
                {
                    ApplicationArea = All;
                }
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                }
                field("Shop Code"; Rec."Shop Code")
                {
                    ApplicationArea = All;
                }
                field("Event Called"; Rec."Event Called")
                {
                    ApplicationArea = All;
                }
                field("Calc Succeeded"; Rec."Calc Succeeded")
                {
                    ApplicationArea = All;
                }
                field("Calculated Price"; Rec."Calculated Price")
                {
                    ApplicationArea = All;
                }
                field("Captured Ending Date"; Rec."Captured Ending Date")
                {
                    ApplicationArea = All;
                }
                field("Error Text"; Rec."Error Text")
                {
                    ApplicationArea = All;
                }
                field(Details; Rec.Details)
                {
                    ApplicationArea = All;
                }
            }
        }
    }
}
