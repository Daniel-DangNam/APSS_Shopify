namespace APSS.Shopify;

table 90301 "APSS Shpfy Reconcile Log"
{
    DataClassification = CustomerContent;
    Caption = 'Shopify Reconcile Log';

    fields
    {
        field(1; "Entry No."; Integer)
        {
            DataClassification = CustomerContent;
            AutoIncrement = true;
            Caption = 'Entry No.';
        }
        field(2; "Logged At"; DateTime)
        {
            DataClassification = CustomerContent;
            Caption = 'Logged At';
        }
        field(3; "Item No."; Code[20])
        {
            DataClassification = CustomerContent;
            Caption = 'Item No.';
        }
        field(4; "Variant Code"; Code[20])
        {
            DataClassification = CustomerContent;
            Caption = 'Variant Code';
        }
        field(5; SKU; Text[50])
        {
            DataClassification = CustomerContent;
            Caption = 'SKU';
        }
        field(6; "Shopify Product Id"; BigInteger)
        {
            DataClassification = CustomerContent;
            Caption = 'Shopify Product Id';
        }
        field(7; "Shopify Variant Id"; BigInteger)
        {
            DataClassification = CustomerContent;
            Caption = 'Shopify Variant Id';
        }
        field(8; "Shopify Handle"; Text[250])
        {
            DataClassification = CustomerContent;
            Caption = 'Shopify Handle';
        }
        field(9; "Shopify Status"; Text[50])
        {
            DataClassification = CustomerContent;
            Caption = 'Shopify Status';
        }
        field(10; Reason; Enum "APSS Shpfy Reconcile Reason")
        {
            DataClassification = CustomerContent;
            Caption = 'Reason';
        }
        field(11; Details; Text[250])
        {
            DataClassification = CustomerContent;
            Caption = 'Details';
        }
        field(12; Resolved; Boolean)
        {
            DataClassification = CustomerContent;
            Caption = 'Resolved';
        }
        field(13; Selected; Boolean)
        {
            DataClassification = CustomerContent;
            Caption = 'Select';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(DeduplicationKey; "Item No.", SKU, Reason, Resolved)
        {
        }
    }

    procedure LogReason(
        ItemNo: Code[20];
        VariantCode: Code[20];
        TargetSKU: Text[50];
        ShopifyProductId: BigInteger;
        ShopifyVariantId: BigInteger;
        ShopifyHandle: Text[250];
        ShopifyStatus: Text[50];
        LogReason: Enum "APSS Shpfy Reconcile Reason";
        LogDetails: Text[250]
    )
    var
        ExistingLog: Record "APSS Shpfy Reconcile Log";
    begin
        ExistingLog.SetRange("Item No.", ItemNo);
        ExistingLog.SetRange(SKU, TargetSKU);
        ExistingLog.SetRange(Reason, LogReason);
        ExistingLog.SetRange(Resolved, false);
        if not ExistingLog.IsEmpty() then
            exit;

        Clear(Rec);
        Rec."Logged At" := CurrentDateTime();
        Rec."Item No." := ItemNo;
        Rec."Variant Code" := VariantCode;
        Rec.SKU := TargetSKU;
        Rec."Shopify Product Id" := ShopifyProductId;
        Rec."Shopify Variant Id" := ShopifyVariantId;
        Rec."Shopify Handle" := ShopifyHandle;
        Rec."Shopify Status" := ShopifyStatus;
        Rec.Reason := LogReason;
        Rec.Details := LogDetails;
        Rec.Resolved := false;
        Rec.Insert(true);
        Commit();
    end;
}
