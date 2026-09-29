namespace APSS.Shopify;

using Microsoft.Integration.Shopify;

tableextension 90301 "APSS Shpfy Shop" extends "Shpfy Shop"
{
    fields
    {
        field(90300; "APSS Procurement Email"; Text[250])
        {
            Caption = 'Procurement Email';
            ExtendedDatatype = EMail;
            ToolTip = 'Specifies the email address of the procurement team to notify upon Shopify synchronization.';
        }
    }
}
