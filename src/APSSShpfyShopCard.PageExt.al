namespace APSS.Shopify;

using Microsoft.Integration.Shopify;

pageextension 90301 "APSS Shpfy Shop Card" extends "Shpfy Shop Card"
{
    layout
    {
        addlast(General)
        {
            field("APSS Procurement Email"; Rec."APSS Procurement Email")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the email address of the procurement team to notify upon Shopify synchronization.';
            }
        }
    }
}
