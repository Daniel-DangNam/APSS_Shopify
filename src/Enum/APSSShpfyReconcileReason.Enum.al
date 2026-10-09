namespace APSS.Shopify;

enum 90301 "APSS Shpfy Reconcile Reason"
{
    Extensible = true;

    value(0; SKU_EXISTS)
    {
        Caption = 'SKU Exists on Shopify';
    }
    value(1; LOOKUP_FAILED)
    {
        Caption = 'GraphQL Lookup Failed';
    }
    value(2; DUPLICATE_SKU_IN_PRODUCT)
    {
        Caption = 'Duplicate SKU in Product Export';
    }
    value(3; ORPHAN_MAPPING)
    {
        Caption = 'Orphaned Shopify Mapping';
    }
    value(4; STALE_MAPPING)
    {
        Caption = 'Stale Mapping';
    }
    value(5; PAYLOAD_SIZE_EXCEEDED)
    {
        Caption = 'Payload Size Exceeded';
    }
}
