tableextension 90300 "APSS Item Shopify Ready" extends Item
{
    fields
    {
        field(90300; "APSS Has Shopify Image"; Boolean)
        {
            Caption = 'Has Shopify Image';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(90301; "APSS Shopify Ready"; Boolean)
        {
            Caption = 'Shopify Ready';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(90302; "APSS Shopify Validation"; Text[250])
        {
            Caption = 'Shopify Validation';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}
