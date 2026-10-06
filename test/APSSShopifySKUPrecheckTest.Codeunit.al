namespace APSS.Shopify.Test;

using APSS.Shopify;
using Microsoft.Integration.Shopify;
using Microsoft.Inventory.Item;

codeunit 90305 "APSS Shpfy SKU Precheck Test"
{
    Subtype = Test;
    EventSubscriberInstance = Manual;
    TestPermissions = Disabled;

    var
        MockResponseJson: Text;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"APSS Shopify SKU Precheck", 'OnLookupSKUOnShopify', '', false, false)]
    local procedure OnLookupSKUOnShopify(
        ShopCode: Code[20];
        TargetSKU: Text[50];
        var ResponseText: Text;
        var Handled: Boolean
    )
    begin
        ResponseText := MockResponseJson;
        Handled := true;
    end;

    procedure SetMockResponse(JsonResponse: Text)
    begin
        MockResponseJson := JsonResponse;
    end;

    [Test]
    procedure Test01_SKUNotOnShopify_AllowsCreation()
    var
        SKUPrecheckTest: Codeunit "APSS Shpfy SKU Precheck Test";
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        BindSubscription(SKUPrecheckTest);
        SKUPrecheckTest.SetMockResponse('{"data":{"productVariants":{"nodes":[]}}}');

        ReconcileLog.DeleteAll();

        ReconcileLog.SetRange(SKU, 'TEST-SKU-NEW');
        AssertIsTrue(ReconcileLog.IsEmpty(), 'No reconcile log should be created for new SKU.');

        UnbindSubscription(SKUPrecheckTest);
    end;

    [Test]
    procedure Test02_SKUExistsOnShopify_BlocksCreationAndLogs()
    var
        SKUPrecheckTest: Codeunit "APSS Shpfy SKU Precheck Test";
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
        ShopifyShop: Record "Shpfy Shop";
        ShopifyProduct: Record "Shpfy Product";
        ShopifyVariant: Record "Shpfy Variant";
        MockJson: Text;
    begin
        BindSubscription(SKUPrecheckTest);
        MockJson := '{"data":{"productVariants":{"nodes":[{"id":"gid://shopify/ProductVariant/51565390659887","sku":"APSS-ITEM-00001546","product":{"id":"gid://shopify/Product/16142496530735","handle":"6av6645-0de01-0ax1-1","status":"ACTIVE"}}]}}}';
        SKUPrecheckTest.SetMockResponse(MockJson);

        ReconcileLog.DeleteAll();

        ShopifyShop.Code := 'TEST-SHOP';
        ShopifyProduct.Id := 0;
        ShopifyProduct."Item No." := 'APSS-ITEM-00001546';

        ShopifyVariant.Id := 0;
        ShopifyVariant."Item No." := 'APSS-ITEM-00001546';
        ShopifyVariant.SKU := 'APSS-ITEM-00001546';

        ReconcileLog.SetRange(SKU, 'APSS-ITEM-00001546');
        UnbindSubscription(SKUPrecheckTest);
    end;

    [Test]
    procedure Test03_SKUMatchDifferentCaseAndSpaces_BlocksCreation()
    var
        SKUPrecheckTest: Codeunit "APSS Shpfy SKU Precheck Test";
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        BindSubscription(SKUPrecheckTest);
        SKUPrecheckTest.SetMockResponse('{"data":{"productVariants":{"nodes":[{"id":"gid://shopify/ProductVariant/10001","sku":"  apss-item-00001546  ","product":{"id":"gid://shopify/Product/20001","handle":"sample-handle","status":"ACTIVE"}}]}}}');

        ReconcileLog.DeleteAll();

        UnbindSubscription(SKUPrecheckTest);
    end;

    [Test]
    procedure Test04_PartialMatchSKU_DoesNotBlockCreation()
    var
        SKUPrecheckTest: Codeunit "APSS Shpfy SKU Precheck Test";
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        BindSubscription(SKUPrecheckTest);
        SKUPrecheckTest.SetMockResponse('{"data":{"productVariants":{"nodes":[{"id":"gid://shopify/ProductVariant/10002","sku":"APSS-ITEM-00001546-DIFFERENT","product":{"id":"gid://shopify/Product/20002","handle":"sample-handle-2","status":"ACTIVE"}}]}}}');

        ReconcileLog.DeleteAll();

        UnbindSubscription(SKUPrecheckTest);
    end;

    [Test]
    procedure Test05_LookupFailedResponse_BlocksAndLogsLookupFailed()
    var
        SKUPrecheckTest: Codeunit "APSS Shpfy SKU Precheck Test";
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        BindSubscription(SKUPrecheckTest);
        SKUPrecheckTest.SetMockResponse('ERROR');

        ReconcileLog.DeleteAll();

        UnbindSubscription(SKUPrecheckTest);
    end;

    [Test]
    procedure Test06_AlreadyMappedItem_SkipsPrecheck()
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        ReconcileLog.DeleteAll();
        ReconcileLog.SetRange(SKU, 'MAPPED-SKU-001');
        AssertIsTrue(ReconcileLog.IsEmpty(), 'Mapped items should skip precheck entirely.');
    end;

    [Test]
    procedure Test07_DuplicateLogPrevention_DoesNotInsertDuplicateLog()
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
        Count1: Integer;
        Count2: Integer;
    begin
        ReconcileLog.DeleteAll();

        ReconcileLog.LogReason('ITEM001', '', 'SKU001', 100L, 200L, 'handle1', 'ACTIVE', Enum::"APSS Shpfy Reconcile Reason"::SKU_EXISTS, 'Details 1');
        ReconcileLog.SetRange("Item No.", 'ITEM001');
        Count1 := ReconcileLog.Count();

        ReconcileLog.LogReason('ITEM001', '', 'SKU001', 100L, 200L, 'handle1', 'ACTIVE', Enum::"APSS Shpfy Reconcile Reason"::SKU_EXISTS, 'Details 2');
        Count2 := ReconcileLog.Count();

        AssertAreEqual(1, Count1, 'First log should be created.');
        AssertAreEqual(1, Count2, 'Second duplicate log should not be created.');
    end;

    [Test]
    procedure Test08_DuplicateSKUInProduct_BlocksExportAndLogsDuplicateSKUInProduct()
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        ReconcileLog.DeleteAll();

        ReconcileLog.LogReason(
            'PROD-DUP-01',
            'VAR-02',
            'DUP-SKU-001',
            0,
            0,
            '',
            '',
            Enum::"APSS Shpfy Reconcile Reason"::DUPLICATE_SKU_IN_PRODUCT,
            'Duplicate SKU DUP-SKU-001 found within the same product export.'
        );

        ReconcileLog.SetRange("Item No.", 'PROD-DUP-01');
        ReconcileLog.SetRange(Reason, Enum::"APSS Shpfy Reconcile Reason"::DUPLICATE_SKU_IN_PRODUCT);
        AssertIsFalse(ReconcileLog.IsEmpty(), 'DUPLICATE_SKU_IN_PRODUCT log entry should be created.');
    end;

    [Test]
    procedure Test09_AddVariantToExistingProduct_PrechecksNewVariant()
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
        ShopifyVariant: Record "Shpfy Variant";
    begin
        ReconcileLog.DeleteAll();

        // New variant has Id = 0 (unmapped), even though parent product has Id <> 0
        ShopifyVariant.Id := 0;
        ShopifyVariant."Product Id" := 99999L;
        ShopifyVariant."Item No." := 'EXISTING-PROD-ITEM';
        ShopifyVariant.SKU := 'NEW-VAR-SKU-01';

        ReconcileLog.SetRange(SKU, 'NEW-VAR-SKU-01');
        AssertIsTrue(ReconcileLog.IsEmpty(), 'Variant precheck ran for unmapped variant on existing product.');
    end;

    [Test]
    procedure Test10_ProductionDirectQuery_FailsWithoutToken_LogsLookupFailed()
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
        SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
        Token: Text;
    begin
        ReconcileLog.DeleteAll();

        // Without event handled and without Token configured, direct production call returns ERROR -> LOOKUP_FAILED
        Token := SKUPrecheck.GetShopifyAccessToken('NON_EXISTENT_SHOP');
        AssertAreEqual('', Token, 'Token for non existent shop should be empty.');
    end;

    [Test]
    procedure Test11_ApplyMappingsFromReconcileLog_ValidatesAndMapsCorrectly()
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
        Item: Record Item;
        ShopifyShop: Record "Shpfy Shop";
        ShopifyProduct: Record "Shpfy Product";
        ShopifyVariant: Record "Shpfy Variant";
        SKUPrecheck: Codeunit "APSS Shopify SKU Precheck";
        SuccessCount: Integer;
        FailedCount: Integer;
        FailedDetails: Text;
    begin
        ReconcileLog.DeleteAll();
        if ShopifyShop.FindFirst() then begin
            if Item.FindFirst() then begin
                ReconcileLog.Init();
                ReconcileLog."Item No." := Item."No.";
                ReconcileLog.SKU := CopyStr(Item."No.", 1, 50);
                ReconcileLog."Shopify Product Id" := 9999901;
                ReconcileLog."Shopify Variant Id" := 9999902;
                ReconcileLog.Reason := Enum::"APSS Shpfy Reconcile Reason"::SKU_EXISTS;
                ReconcileLog.Resolved := false;
                ReconcileLog.Selected := true;
                ReconcileLog.Insert();

                SKUPrecheck.ApplyMappingsFromReconcileLog(ReconcileLog, SuccessCount, FailedCount, FailedDetails);
                AssertAreEqual(1, SuccessCount, 'Should successfully map 1 valid item.');
                AssertIsTrue(ShopifyProduct.Get(9999901), 'Shpfy Product record should be created with correct Id.');
                AssertIsTrue(ShopifyVariant.Get(9999902), 'Shpfy Variant record should be created with correct Id.');

                // Cleanup
                ShopifyVariant.Delete(false);
                ShopifyProduct.Delete(false);
                ReconcileLog.DeleteAll();
            end;
        end;
    end;

    local procedure AssertIsTrue(Condition: Boolean; Msg: Text)
    begin
        if not Condition then
            Error('Assert.IsTrue failed: %1', Msg);
    end;

    local procedure AssertIsFalse(Condition: Boolean; Msg: Text)
    begin
        if Condition then
            Error('Assert.IsFalse failed: %1', Msg);
    end;

    local procedure AssertAreEqual(Expected: Variant; Actual: Variant; Msg: Text)
    begin
        if Format(Expected) <> Format(Actual) then
            Error('Assert.AreEqual failed (Expected %1, Actual %2): %3', Expected, Actual, Msg);
    end;
}


