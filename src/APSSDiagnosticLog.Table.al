namespace Microsoft.Integration.Shopify;

table 90305 "APSS Diagnostic Log"
{
    DataClassification = CustomerContent;
    Caption = 'APSS Diagnostic Log';

    fields
    {
        field(1; "Entry No."; BigInteger)
        {
            AutoIncrement = true;
            Caption = 'Entry No.';
        }
        field(2; "Date Time"; DateTime)
        {
            Caption = 'Date Time';
        }
        field(3; "Context"; Text[100])
        {
            Caption = 'Context';
        }
        field(4; "Item No."; Code[20])
        {
            Caption = 'Item No.';
        }
        field(5; "Shop Code"; Code[20])
        {
            Caption = 'Shop Code';
        }
        field(6; "Event Called"; Boolean)
        {
            Caption = 'Event Called';
        }
        field(7; "Calc Succeeded"; Boolean)
        {
            Caption = 'Calc Succeeded';
        }
        field(8; "Calculated Price"; Decimal)
        {
            Caption = 'Calculated Price';
        }
        field(9; "Captured Ending Date"; Date)
        {
            Caption = 'Captured Ending Date';
        }
        field(10; "Error Text"; Text[2048])
        {
            Caption = 'Error Text';
        }
        field(11; "Details"; Text[250])
        {
            Caption = 'Details';
        }
        field(12; "Session ID"; Integer)
        {
            Caption = 'Session ID';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }
}
