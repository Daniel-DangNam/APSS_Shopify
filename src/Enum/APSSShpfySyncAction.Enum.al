namespace APSS.Shopify;

enum 90302 "APSS Shpfy Sync Action"
{
    Extensible = true;

    value(0; None)
    {
        Caption = 'None';
    }
    value(1; Create)
    {
        Caption = 'Create';
    }
    value(2; Update)
    {
        Caption = 'Update';
    }
    value(3; Block_NeedsReconciliation)
    {
        Caption = 'Block (Needs Reconciliation)';
    }
    value(4; Block_StaleMapping)
    {
        Caption = 'Block (Stale Mapping)';
    }
}
