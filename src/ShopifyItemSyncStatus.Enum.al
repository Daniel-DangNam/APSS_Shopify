namespace Microsoft.Integration.Shopify;

enum 90300 "APSS Shopify Item Sync Status"
{
    Extensible = true;

    value(0; "Not Ready")
    {
        Caption = 'Not Ready';
    }
    value(1; "New Ready")
    {
        Caption = 'New Ready';
    }
    value(2; "Modified Ready")
    {
        Caption = 'Modified Ready';
    }
    value(3; "Synced Unchanged")
    {
        Caption = 'Synced Unchanged';
    }
}
