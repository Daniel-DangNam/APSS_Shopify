namespace Microsoft.Integration.Shopify;

using Microsoft.Inventory.Item;

table 90306 "APSS Item Price Ending Date"
{
    Caption = 'APSS Item Price Ending Date';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            DataClassification = CustomerContent;
            TableRelation = Item;
        }
        field(2; "Shop Code"; Code[20])
        {
            Caption = 'Shop Code';
            DataClassification = CustomerContent;
            TableRelation = "Shpfy Shop";
        }
        field(3; "Ending Date"; Date)
        {
            Caption = 'Ending Date';
            DataClassification = CustomerContent;
        }
        field(4; "Has Variant Conflict"; Boolean)
        {
            Caption = 'Has Variant Conflict';
            DataClassification = CustomerContent;
        }
        field(5; "Last Updated"; DateTime)
        {
            Caption = 'Last Updated';
            DataClassification = CustomerContent;
        }
        field(6; "Last Session ID"; Integer)
        {
            Caption = 'Last Session ID';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "Item No.", "Shop Code")
        {
            Clustered = true;
        }
    }
}
