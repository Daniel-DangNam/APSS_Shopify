namespace Microsoft.Integration.Shopify;

using Microsoft.Inventory.Item;

table 90300 "APSS Shpfy Item Sel. Buffer"
{
    DataClassification = SystemMetadata;
    TableType = Temporary;
    Caption = 'Shopify Item Selection Buffer';

    fields
    {
        field(1; "Item No."; Code[20])
        {
            DataClassification = SystemMetadata;
            Caption = 'No.';
            TableRelation = Item."No.";
        }
        field(2; Selected; Boolean)
        {
            DataClassification = SystemMetadata;
            Caption = 'Select';
        }
        field(3; Description; Text[100])
        {
            DataClassification = SystemMetadata;
            Caption = 'Description';
        }
        field(4; "Has Shopify Image"; Boolean)
        {
            DataClassification = SystemMetadata;
            Caption = 'Has Shopify Image';
        }
        field(5; "Shopify Ready"; Boolean)
        {
            DataClassification = SystemMetadata;
            Caption = 'Shopify Ready';
        }
        field(6; "Sync Status"; Enum "APSS Shopify Item Sync Status")
        {
            DataClassification = SystemMetadata;
            Caption = 'Shopify Sync Status';
        }
        field(7; "Sync Status Style"; Text[30])
        {
            DataClassification = SystemMetadata;
        }
    }

    keys
    {
        key(PK; "Item No.")
        {
            Clustered = true;
        }
    }
}
