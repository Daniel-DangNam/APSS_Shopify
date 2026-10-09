namespace APSS.Shopify;

using Microsoft.Integration.Shopify;
using Microsoft.Inventory.Item;
using System.Text;

codeunit 90304 "APSS Shopify SKU Precheck"
{
    [IntegrationEvent(false, false)]
    procedure OnLookupSKUOnShopify(
        ShopCode: Code[20];
        TargetSKU: Text[50];
        var ResponseText: Text;
        var Handled: Boolean
    )
    begin
    end;

    procedure SetShopifyClientId(ShopCode: Code[20]; ClientId: Text)
    begin
        if ClientId = '' then
            IsolatedStorage.Delete(GetClientIdKey(ShopCode), DataScope::Module)
        else
            IsolatedStorage.Set(GetClientIdKey(ShopCode), ClientId, DataScope::Module);
    end;

    procedure GetShopifyClientId(ShopCode: Code[20]): Text
    var
        Shop: Record "Shpfy Shop";
        ClientId: Text;
    begin
        if IsolatedStorage.Get(GetClientIdKey(ShopCode), DataScope::Module, ClientId) then
            if ClientId <> '' then
                exit(ClientId);
        if Shop.Get(ShopCode) then
            if Shop."APSS Client ID" <> '' then
                exit(Shop."APSS Client ID");
        exit('');
    end;

    procedure SetShopifyClientSecret(ShopCode: Code[20]; ClientSecret: Text)
    begin
        if ClientSecret = '' then
            IsolatedStorage.Delete(GetClientSecretKey(ShopCode), DataScope::Module)
        else
            IsolatedStorage.Set(GetClientSecretKey(ShopCode), ClientSecret, DataScope::Module);
    end;

    procedure GetShopifyClientSecret(ShopCode: Code[20]): Text
    var
        ClientSecret: Text;
    begin
        if IsolatedStorage.Get(GetClientSecretKey(ShopCode), DataScope::Module, ClientSecret) then
            exit(ClientSecret);
        exit('');
    end;

    procedure SetShopifyAccessToken(ShopCode: Code[20]; Token: Text)
    begin
        if Token = '' then begin
            IsolatedStorage.Delete(GetTokenKey(ShopCode), DataScope::Module);
            IsolatedStorage.Delete(GetTokenExpiryKey(ShopCode), DataScope::Module);
        end else
            IsolatedStorage.Set(GetTokenKey(ShopCode), Token, DataScope::Module);
    end;

    procedure GetShopifyAccessToken(ShopCode: Code[20]): Text
    var
        CachedToken: Text;
        ExpiryText: Text;
        ExpiryDateTime: DateTime;
    begin
        // 1. Check if cached non-expired token is present (with 5-minute safety buffer)
        if IsolatedStorage.Get(GetTokenKey(ShopCode), DataScope::Module, CachedToken) then
            if CachedToken <> '' then
                if IsolatedStorage.Get(GetTokenExpiryKey(ShopCode), DataScope::Module, ExpiryText) then
                    if Evaluate(ExpiryDateTime, ExpiryText) then
                        if CurrentDateTime() < (ExpiryDateTime - 300000) then
                            exit(CachedToken);

        // 2. Refresh access token via OAuth client_credentials flow
        CachedToken := RefreshAccessTokenViaOAuth(ShopCode);
        if CachedToken <> '' then
            exit(CachedToken);

        // 3. Fallback to manually stored token if any
        if IsolatedStorage.Get(GetTokenKey(ShopCode), DataScope::Module, CachedToken) then
            exit(CachedToken);

        exit('');
    end;

    procedure RefreshAccessTokenViaOAuth(ShopCode: Code[20]): Text
    var
        ShopifyShop: Record "Shpfy Shop";
        HttpClient: HttpClient;
        HttpHeaders: HttpHeaders;
        HttpContent: HttpContent;
        HttpResponseMessage: HttpResponseMessage;
        JResponse: JsonToken;
        JObj: JsonObject;
        JTokenVal: JsonToken;
        ShopUrl: Text;
        OAuthUrl: Text;
        ClientId: Text;
        ClientSecret: Text;
        RequestBody: Text;
        ResponseText: Text;
        NewAccessToken: Text;
        ExpiresInSec: Integer;
        ExpiryDateTime: DateTime;
    begin
        if not ShopifyShop.Get(ShopCode) then
            exit('');

        ShopUrl := GetShopUrl(ShopifyShop);
        if ShopUrl = '' then
            exit('');

        ClientId := GetShopifyClientId(ShopCode);
        ClientSecret := GetShopifyClientSecret(ShopCode);

        if (ClientId = '') or (ClientSecret = '') then
            exit('');

        OAuthUrl := ShopUrl + '/admin/oauth/access_token';
        RequestBody := StrSubstNo('client_id=%1&client_secret=%2&grant_type=client_credentials', ClientId, ClientSecret);

        HttpContent.WriteFrom(RequestBody);
        HttpContent.GetHeaders(HttpHeaders);
        HttpHeaders.Remove('Content-Type');
        HttpHeaders.Add('Content-Type', 'application/x-www-form-urlencoded');

        if HttpClient.Post(OAuthUrl, HttpContent, HttpResponseMessage) then begin
            HttpResponseMessage.Content().ReadAs(ResponseText);
            if HttpResponseMessage.IsSuccessStatusCode() then begin
                if JResponse.ReadFrom(ResponseText) and JResponse.IsObject() then begin
                    JObj := JResponse.AsObject();
                    if JObj.Get('access_token', JTokenVal) then
                        NewAccessToken := JTokenVal.AsValue().AsText();

                    ExpiresInSec := 86400;
                    if JObj.Get('expires_in', JTokenVal) then
                        ExpiresInSec := JTokenVal.AsValue().AsInteger();

                    if NewAccessToken <> '' then begin
                        ExpiryDateTime := CurrentDateTime() + (ExpiresInSec * 1000);
                        IsolatedStorage.Set(GetTokenKey(ShopCode), NewAccessToken, DataScope::Module);
                        IsolatedStorage.Set(GetTokenExpiryKey(ShopCode), Format(ExpiryDateTime, 0, 9), DataScope::Module);
                        exit(NewAccessToken);
                    end;
                end;
            end;
        end;

        exit('');
    end;

    procedure TestShopifyConnection(ShopCode: Code[20])
    var
        ShopifyShop: Record "Shpfy Shop";
        ShopUrl: Text;
        ClientId: Text;
        ClientSecret: Text;
        HttpClient: HttpClient;
        HttpHeaders: HttpHeaders;
        HttpContent: HttpContent;
        HttpResponseMessage: HttpResponseMessage;
        OAuthUrl: Text;
        RequestBody: Text;
        ResponseText: Text;
        Token: Text;
    begin
        if not ShopifyShop.Get(ShopCode) then
            Error('Shop %1 not found.', ShopCode);

        ShopUrl := GetShopUrl(ShopifyShop);
        if ShopUrl = '' then
            Error('Shopify Store URL is not configured on Shopify Shop Card.');

        ClientId := GetShopifyClientId(ShopCode);
        ClientSecret := GetShopifyClientSecret(ShopCode);

        if (ClientId <> '') and (ClientSecret <> '') then begin
            OAuthUrl := ShopUrl + '/admin/oauth/access_token';
            RequestBody := StrSubstNo('client_id=%1&client_secret=%2&grant_type=client_credentials', ClientId, ClientSecret);

            HttpContent.WriteFrom(RequestBody);
            HttpContent.GetHeaders(HttpHeaders);
            HttpHeaders.Remove('Content-Type');
            HttpHeaders.Add('Content-Type', 'application/x-www-form-urlencoded');

            if not HttpClient.Post(OAuthUrl, HttpContent, HttpResponseMessage) then
                Error('Network error when contacting Shopify at %1.', OAuthUrl);

            HttpResponseMessage.Content().ReadAs(ResponseText);
            if not HttpResponseMessage.IsSuccessStatusCode() then begin
                if ResponseText.Contains('app_not_installed') then
                    Error('Shopify Error: app_not_installed.\\The App (Client ID: %1) has not been installed on store %2.\\Please install the app on the store via Shopify Partner Dashboard or Organization settings.', ClientId, ShopUrl);
                if ResponseText.Contains('shop_not_permitted') then
                    Error('Shopify Error: shop_not_permitted.\\The App and store %1 are not in the same Shopify organization.', ShopUrl);
                Error('Failed to refresh token from Shopify (HTTP %1):\\%2', HttpResponseMessage.HttpStatusCode(), ResponseText);
            end;
        end;

        Token := GetShopifyAccessToken(ShopCode);
        if Token = '' then
            Error('No valid Access Token available.\\Please configure Client ID & Client Secret or enter a manual Shopify Token.');

        ResponseText := QueryShopifyGraphQLDirectly(ShopCode, '__APSS_PING__');
        if (ResponseText = '') or (ResponseText = 'ERROR') then
            Error('Access Token obtained, but GraphQL query failed.\\Please check Admin API permissions (read_products).')
        else if ResponseText.Contains('"errors"') and not ResponseText.Contains('"data"') then
            Error('Shopify GraphQL Error:\\%1', ResponseText)
        else
            Message('Success! Shopify OAuth connection verified successfully.\\Auto-refreshing access token is active on %1.', ShopUrl);
    end;

    local procedure GetClientIdKey(ShopCode: Code[20]): Text
    begin
        exit(StrSubstNo('APSS_Shopify_ClientId_%1', ShopCode));
    end;

    local procedure GetClientSecretKey(ShopCode: Code[20]): Text
    begin
        exit(StrSubstNo('APSS_Shopify_ClientSecret_%1', ShopCode));
    end;

    local procedure GetTokenKey(ShopCode: Code[20]): Text
    begin
        exit(StrSubstNo('APSS_Shopify_Token_%1', ShopCode));
    end;

    local procedure GetTokenExpiryKey(ShopCode: Code[20]): Text
    begin
        exit(StrSubstNo('APSS_Shopify_TokenExpiry_%1', ShopCode));
    end;

    procedure IsPrecheckEnabled(ShopCode: Code[20]): Boolean
    var
        Shop: Record "Shpfy Shop";
    begin
        if Shop.Get(ShopCode) then
            exit(Shop."APSS Enable SKU Precheck");
        exit(true);
    end;

    /// <summary>
    /// Evaluates sync eligibility for an item across the 4 core branches:
    /// Branch 1 (Update): Mapping exists and Product ID exists on Shopify -> returns true, Action = Update
    /// Branch 2 (Create): No mapping and SKU clear on Shopify -> returns true, Action = Create
    /// Branch 3 (Block Create): No mapping but SKU exists on Shopify -> returns false, Action = Block_NeedsReconciliation
    /// Branch 4 (Stale Mapping): Mapping exists but Product ID missing on Shopify -> returns false, Action = Block_StaleMapping
    /// </summary>
    procedure EvaluateItemSyncEligibility(
        ShopCode: Code[20];
        Item: Record Item;
        var BatchSKUsList: List of [Text];
        var SyncAction: Enum "APSS Shpfy Sync Action";
        var ReasonText: Text
    ): Boolean
    var
        ShopifyProduct: Record "Shpfy Product";
        ShopifyShop: Record "Shpfy Shop";
        TargetSKU: Text[50];
        NormalizedSKU: Text[50];
        SKUsToCheck: List of [Text];
        SKUItem: Text;
        ProductIdExists: Boolean;
    begin
        Clear(SyncAction);
        ReasonText := '';

        if not IsPrecheckEnabled(ShopCode) then begin
            SyncAction := SyncAction::Create;
            exit(true);
        end;

        if not ShopifyShop.Get(ShopCode) then
            exit(false);

        // Pre-check payload size (Marketing Text length & embedded Base64 images)
        if not CheckItemPayloadLimit(Item, ReasonText) then begin
            SyncAction := SyncAction::Block_NeedsReconciliation;
            LogReconcileReason(
                Item."No.",
                '',
                CopyStr(Item."No.", 1, 50),
                0,
                0,
                Item.Description,
                'Draft',
                Enum::"APSS Shpfy Reconcile Reason"::PAYLOAD_SIZE_EXCEEDED,
                ReasonText
            );
            exit(false);
        end;

        // Check if BC already has a valid mapping (Id <> 0)
        ShopifyProduct.SetRange("Shop Code", ShopCode);
        ShopifyProduct.SetRange("Item SystemId", Item.SystemId);
        ShopifyProduct.SetFilter(Id, '<>0');

        if ShopifyProduct.FindFirst() then begin
            // BRANCH 1 & BRANCH 4: Mapping exists in BC
            ProductIdExists := CheckShopifyProductIdExists(ShopCode, ShopifyProduct.Id);
            if ProductIdExists then begin
                // BRANCH 1: BC mapping exists AND Product ID exists on Shopify -> UPDATE
                SyncAction := SyncAction::Update;
                exit(true);
            end else begin
                // BRANCH 4: BC mapping exists BUT Product ID missing on Shopify -> STALE MAPPING
                SyncAction := SyncAction::Block_StaleMapping;
                ReasonText := StrSubstNo('Shopify Product ID %1 no longer exists on Shopify Admin (Stale Mapping).', ShopifyProduct.Id);
                LogReconcileReason(
                    Item."No.",
                    '',
                    '',
                    ShopifyProduct.Id,
                    0,
                    ShopifyProduct.Title,
                    Format(ShopifyProduct.Status),
                    Enum::"APSS Shpfy Reconcile Reason"::STALE_MAPPING,
                    ReasonText
                );
                exit(false);
            end;
        end else begin
            // BRANCH 2 & BRANCH 3: No mapping in BC
            // Clean up any transient/incomplete Id = 0 records for this item
            PurgeGhostRecordsForItem(ShopCode, Item.SystemId);

            // Collect all potential SKUs for this item
            GetItemSKUs(ShopifyShop, Item, SKUsToCheck);
            if SKUsToCheck.Count() = 0 then
                SKUsToCheck.Add(CopyStr(Item."No.", 1, 50));

            foreach SKUItem in SKUsToCheck do begin
                TargetSKU := CopyStr(SKUItem, 1, 50);
                NormalizedSKU := TargetSKU.Trim().ToUpper();

                // Check duplicate in current batch
                if BatchSKUsList.Contains(NormalizedSKU) then begin
                    SyncAction := SyncAction::Block_NeedsReconciliation;
                    ReasonText := StrSubstNo('Duplicate SKU %1 found within the current sync batch.', TargetSKU);
                    LogReconcileReason(
                        Item."No.",
                        '',
                        TargetSKU,
                        0,
                        0,
                        Item.Description,
                        'Draft',
                        Enum::"APSS Shpfy Reconcile Reason"::DUPLICATE_SKU_IN_PRODUCT,
                        ReasonText
                    );
                    exit(false);
                end;

                // Check SKU on Shopify Admin
                if not VerifySKUOnShopify(ShopCode, Item."No.", '', TargetSKU, Item.Description, ReasonText) then begin
                    // BRANCH 3: No mapping BUT SKU exists on Shopify -> BLOCK CREATE & NEEDS RECONCILIATION
                    SyncAction := SyncAction::Block_NeedsReconciliation;
                    exit(false);
                end;
            end;

            // BRANCH 2: No mapping AND SKU does not exist on Shopify -> CREATE
            foreach SKUItem in SKUsToCheck do
                BatchSKUsList.Add(SKUItem.Trim().ToUpper());

            SyncAction := SyncAction::Create;
            exit(true);
        end;
    end;

    procedure GetShopUrl(Shop: Record "Shpfy Shop"): Text
    var
        Url: Text;
    begin
        Url := Shop."APSS Shopify URL";
        if Url = '' then
            exit('');
        if not Url.ToLower().StartsWith('https://') then
            Url := 'https://' + Url;
        exit(Url.TrimEnd('/'));
    end;

    local procedure CheckShopifyProductIdExists(ShopCode: Code[20]; ShopifyProductId: BigInteger): Boolean
    var
        ResponseText: Text;
        Token: Text;
        ShopUrl: Text;
        GraphQLUrl: Text;
        GraphQLQuery: Text;
        HttpClient: HttpClient;
        HttpHeaders: HttpHeaders;
        HttpContent: HttpContent;
        HttpResponseMessage: HttpResponseMessage;
        JReqObj: JsonObject;
        JResponse: JsonToken;
        JData: JsonObject;
        JProdToken: JsonToken;
        ShopifyShop: Record "Shpfy Shop";
    begin
        if ShopifyProductId = 0 then
            exit(false);

        Token := GetShopifyAccessToken(ShopCode);
        if not ShopifyShop.Get(ShopCode) then
            exit(true);

        ShopUrl := GetShopUrl(ShopifyShop);
        if (Token = '') or (ShopUrl = '') then
            exit(true); // If token/URL not configured, fallback to allowing update

        GraphQLUrl := ShopUrl + '/admin/api/2024-01/graphql.json';
        GraphQLQuery := StrSubstNo('{ product(id: "gid://shopify/Product/%1") { id status } }', ShopifyProductId);

        JReqObj.Add('query', GraphQLQuery);
        JReqObj.WriteTo(ResponseText);

        HttpContent.WriteFrom(ResponseText);
        HttpContent.GetHeaders(HttpHeaders);
        HttpHeaders.Remove('Content-Type');
        HttpHeaders.Add('Content-Type', 'application/json');

        HttpClient.DefaultRequestHeaders().Add('X-Shopify-Access-Token', Token);

        if HttpClient.Post(GraphQLUrl, HttpContent, HttpResponseMessage) then
            if HttpResponseMessage.IsSuccessStatusCode() then begin
                HttpResponseMessage.Content().ReadAs(ResponseText);
                if JResponse.ReadFrom(ResponseText) and JResponse.IsObject() then begin
                    JData := JResponse.AsObject();
                    if JData.Get('data', JProdToken) and JProdToken.IsObject() then
                        if JProdToken.AsObject().Get('product', JProdToken) then begin
                            if JProdToken.IsObject() then
                                exit(true);
                            if JProdToken.IsValue() then
                                exit(not JProdToken.AsValue().IsNull());
                        end;
                end;
            end;

        exit(true); // Network/lookup failure defaults to allowing update
    end;

    local procedure GetItemSKUs(
        Shop: Record "Shpfy Shop";
        Item: Record Item;
        var SKUsList: List of [Text]
    )
    var
        ItemVariant: Record "Item Variant";
        ItemUOM: Record "Item Unit of Measure";
        TargetSKU: Text[50];
    begin
        ItemVariant.SetRange("Item No.", Item."No.");
        if ItemVariant.FindSet() then
            repeat
                TargetSKU := GetCalculatedSKU(Shop, Item."No.", ItemVariant.Code, Item."Vendor Item No.");
                if TargetSKU <> '' then
                    SKUsList.Add(TargetSKU);
            until ItemVariant.Next() = 0
        else
            if Shop."UoM as Variant" then begin
                ItemUOM.SetRange("Item No.", Item."No.");
                if ItemUOM.FindSet() then
                    repeat
                        TargetSKU := GetCalculatedSKU(Shop, Item."No.", '', Item."Vendor Item No.");
                        if TargetSKU <> '' then
                            if not SKUsList.Contains(TargetSKU) then
                                SKUsList.Add(TargetSKU);
                    until ItemUOM.Next() = 0;
            end else begin
                TargetSKU := GetCalculatedSKU(Shop, Item."No.", '', Item."Vendor Item No.");
                if TargetSKU <> '' then
                    SKUsList.Add(TargetSKU);
            end;
    end;

    local procedure GetCalculatedSKU(
        Shop: Record "Shpfy Shop";
        ItemNo: Code[20];
        VariantCode: Code[10];
        VendorItemNo: Text[50]
    ): Text[50]
    begin
        case Shop."SKU Mapping" of
            Shop."SKU Mapping"::"Item No.":
                exit(CopyStr(ItemNo, 1, 50));
            Shop."SKU Mapping"::"Variant Code":
                if VariantCode <> '' then
                    exit(CopyStr(VariantCode, 1, 50));
            Shop."SKU Mapping"::"Item No. + Variant Code":
                if VariantCode <> '' then
                    exit(CopyStr(ItemNo + Shop."SKU Field Separator" + VariantCode, 1, 50))
                else
                    exit(CopyStr(ItemNo, 1, 50));
            Shop."SKU Mapping"::"Vendor Item No.":
                exit(VendorItemNo);
            else
                exit(CopyStr(ItemNo, 1, 50));
        end;
    end;

    local procedure VerifySKUOnShopify(
        ShopCode: Code[20];
        ItemNo: Code[20];
        VariantCode: Code[20];
        TargetSKU: Text[50];
        ProductTitle: Text[250];
        var ReasonText: Text
    ): Boolean
    var
        ResponseText: Text;
        Handled: Boolean;
        QueryFailed: Boolean;
        JResponse: JsonToken;
        JData: JsonObject;
        JNodeToken: JsonToken;
        JNodes: JsonArray;
        JNodeObj: JsonObject;
        JProductObj: JsonObject;
        NodeToken: JsonToken;
        NodeSKU: Text;
        NodeVariantGId: Text;
        NodeProductGId: Text;
        NodeHandle: Text;
        NodeStatus: Text;
        ShopifyVariantId: BigInteger;
        ShopifyProductId: BigInteger;
        MatchedCount: Integer;
        i: Integer;
    begin
        OnLookupSKUOnShopify(ShopCode, TargetSKU, ResponseText, Handled);

        if not Handled then begin
            if GetShopifyAccessToken(ShopCode) <> '' then
                ResponseText := QueryShopifyGraphQLDirectly(ShopCode, TargetSKU)
            else
                exit(CheckLocalVariantTable(ItemNo, VariantCode, TargetSKU, ProductTitle, ReasonText));
        end;

        if (ResponseText = '') or (ResponseText = 'ERROR') then
            QueryFailed := true
        else if not JResponse.ReadFrom(ResponseText) then
            QueryFailed := true;

        if QueryFailed or not JResponse.IsObject() then begin
            ReasonText := StrSubstNo('GraphQL lookup failed for SKU %1 (Fail-Closed).', TargetSKU);
            LogReconcileReason(ItemNo, VariantCode, TargetSKU, 0, 0, ProductTitle, 'Draft', Enum::"APSS Shpfy Reconcile Reason"::LOOKUP_FAILED, ReasonText);
            exit(false);
        end;

        JData := JResponse.AsObject();
        if not JData.Get('data', JNodeToken) then
            QueryFailed := true
        else if not JNodeToken.AsObject().Get('productVariants', JNodeToken) then
            QueryFailed := true
        else if not JNodeToken.AsObject().Get('nodes', JNodeToken) then
            QueryFailed := true;

        if QueryFailed or not JNodeToken.IsArray() then begin
            ReasonText := StrSubstNo('Invalid GraphQL response structure for SKU %1 (LOOKUP_FAILED).', TargetSKU);
            LogReconcileReason(ItemNo, VariantCode, TargetSKU, 0, 0, ProductTitle, 'Draft', Enum::"APSS Shpfy Reconcile Reason"::LOOKUP_FAILED, ReasonText);
            exit(false);
        end;

        JNodes := JNodeToken.AsArray();
        MatchedCount := 0;

        for i := 0 to JNodes.Count() - 1 do begin
            JNodes.Get(i, NodeToken);
            if NodeToken.IsObject() then begin
                JNodeObj := NodeToken.AsObject();
                NodeSKU := GetJsonString(JNodeObj, 'sku');
                
                if NodeSKU.Trim().ToUpper() = TargetSKU.Trim().ToUpper() then begin
                    MatchedCount += 1;
                    NodeVariantGId := GetJsonString(JNodeObj, 'id');
                    ShopifyVariantId := GetIdOfGId(NodeVariantGId);

                    if JNodeObj.Get('product', NodeToken) then
                        if NodeToken.IsObject() then begin
                            JProductObj := NodeToken.AsObject();
                            NodeProductGId := GetJsonString(JProductObj, 'id');
                            ShopifyProductId := GetIdOfGId(NodeProductGId);
                            NodeHandle := GetJsonString(JProductObj, 'handle');
                            NodeStatus := GetJsonString(JProductObj, 'status');
                        end;

                    if NodeHandle = '' then
                        NodeHandle := ProductTitle;

                    ReasonText := StrSubstNo('SKU %1 already exists on Shopify (Product ID %2, Variant ID %3, Handle: %4).', TargetSKU, ShopifyProductId, ShopifyVariantId, NodeHandle);
                    LogReconcileReason(ItemNo, VariantCode, TargetSKU, ShopifyProductId, ShopifyVariantId, NodeHandle, NodeStatus, Enum::"APSS Shpfy Reconcile Reason"::SKU_EXISTS, ReasonText);
                end;
            end;
        end;

        exit(MatchedCount = 0);
    end;

    local procedure CheckLocalVariantTable(
        ItemNo: Code[20];
        VariantCode: Code[20];
        TargetSKU: Text[50];
        ProductTitle: Text[250];
        var ReasonText: Text
    ): Boolean
    var
        ExistingShpfyVariant: Record "Shpfy Variant";
        ExistingShpfyProduct: Record "Shpfy Product";
        MatchedCount: Integer;
        ShopifyProductId: BigInteger;
        ShopifyVariantId: BigInteger;
        NodeHandle: Text[250];
        NodeStatus: Text[50];
    begin
        ExistingShpfyVariant.SetRange(SKU, TargetSKU);
        if ExistingShpfyVariant.FindSet() then
            repeat
                if ExistingShpfyVariant.Id <> 0 then begin
                    MatchedCount += 1;
                    ShopifyVariantId := ExistingShpfyVariant.Id;
                    ShopifyProductId := ExistingShpfyVariant."Product Id";
                    NodeHandle := ProductTitle;
                    NodeStatus := 'Active';

                    if ExistingShpfyProduct.Get(ShopifyProductId) then begin
                        if ExistingShpfyProduct.Title <> '' then
                            NodeHandle := ExistingShpfyProduct.Title;
                        NodeStatus := Format(ExistingShpfyProduct.Status);
                    end;

                    ReasonText := StrSubstNo('SKU %1 already exists on Shopify (Product ID %2, Variant ID %3).', TargetSKU, ShopifyProductId, ShopifyVariantId);
                    LogReconcileReason(ItemNo, VariantCode, TargetSKU, ShopifyProductId, ShopifyVariantId, NodeHandle, NodeStatus, Enum::"APSS Shpfy Reconcile Reason"::SKU_EXISTS, ReasonText);
                end;
            until ExistingShpfyVariant.Next() = 0;

        exit(MatchedCount = 0);
    end;

    local procedure QueryShopifyGraphQLDirectly(ShopCode: Code[20]; TargetSKU: Text[50]): Text
    var
        ShopifyShop: Record "Shpfy Shop";
        HttpClient: HttpClient;
        HttpHeaders: HttpHeaders;
        HttpContent: HttpContent;
        HttpResponseMessage: HttpResponseMessage;
        JReqObj: JsonObject;
        GraphQLQuery: Text;
        ReqText: Text;
        ResponseText: Text;
        Token: Text;
        ShopUrl: Text;
        GraphQLUrl: Text;
        CleanSKU: Text;
    begin
        if not ShopifyShop.Get(ShopCode) then
            exit('ERROR');

        ShopUrl := GetShopUrl(ShopifyShop);
        if ShopUrl = '' then
            exit('ERROR');

        GraphQLUrl := ShopUrl + '/admin/api/2024-01/graphql.json';

        Token := GetShopifyAccessToken(ShopCode);
        if Token = '' then
            exit('ERROR');

        CleanSKU := TargetSKU.Trim().Replace('\', '\\').Replace('"', '\"');
        GraphQLQuery := StrSubstNo('{ productVariants(first: 10, query: "sku:\"%1\"") { nodes { id sku product { id handle status } } } }', CleanSKU);

        JReqObj.Add('query', GraphQLQuery);
        JReqObj.WriteTo(ReqText);

        HttpContent.WriteFrom(ReqText);
        HttpContent.GetHeaders(HttpHeaders);
        HttpHeaders.Remove('Content-Type');
        HttpHeaders.Add('Content-Type', 'application/json');

        HttpClient.DefaultRequestHeaders().Add('X-Shopify-Access-Token', Token);

        if not HttpClient.Post(GraphQLUrl, HttpContent, HttpResponseMessage) then
            exit('ERROR');

        if not HttpResponseMessage.IsSuccessStatusCode() then
            exit('ERROR');

        HttpResponseMessage.Content().ReadAs(ResponseText);
        exit(ResponseText);
    end;

    /// <summary>
    /// Purges all incomplete / ghost records (Id = 0) from BC Shpfy Product and Variant tables.
    /// </summary>
    procedure PurgeIncompleteRecords(ShopCode: Code[20])
    var
        GhostProd: Record "Shpfy Product";
        GhostVar: Record "Shpfy Variant";
    begin
        if ShopCode <> '' then begin
            GhostVar.SetRange("Shop Code", ShopCode);
            GhostProd.SetRange("Shop Code", ShopCode);
        end;

        GhostVar.SetRange(Id, 0);
        if not GhostVar.IsEmpty() then
            GhostVar.DeleteAll(true);

        GhostProd.SetRange(Id, 0);
        if not GhostProd.IsEmpty() then
            GhostProd.DeleteAll(true);
    end;

    local procedure PurgeGhostRecordsForItem(ShopCode: Code[20]; ItemSystemId: Guid)
    var
        GhostProd: Record "Shpfy Product";
        GhostVar: Record "Shpfy Variant";
    begin
        if IsNullGuid(ItemSystemId) then
            exit;

        GhostVar.SetRange("Shop Code", ShopCode);
        GhostVar.SetRange("Item SystemId", ItemSystemId);
        GhostVar.SetRange(Id, 0);
        if not GhostVar.IsEmpty() then
            GhostVar.DeleteAll(true);

        GhostProd.SetRange("Shop Code", ShopCode);
        GhostProd.SetRange("Item SystemId", ItemSystemId);
        GhostProd.SetRange(Id, 0);
        if not GhostProd.IsEmpty() then
            GhostProd.DeleteAll(true);
    end;

    /// <summary>
    /// Scans for orphaned mappings (Shpfy Product with non-zero Id that no longer exists on Shopify Admin).
    /// Logs findings into APSS Shpfy Reconcile Log without deleting records.
    /// </summary>
    procedure ScanOrphanedMappings(ShopCode: Code[20]; var OrphanCount: Integer)
    var
        ShpfyProduct: Record "Shpfy Product";
        Item: Record Item;
        Token: Text;
        ShopUrl: Text;
        ShopifyShop: Record "Shpfy Shop";
        HttpClient: HttpClient;
        HttpHeaders: HttpHeaders;
        HttpContent: HttpContent;
        HttpResponseMessage: HttpResponseMessage;
        JReqObj: JsonObject;
        JResponse: JsonToken;
        JData: JsonObject;
        JProdToken: JsonToken;
        GraphQLQuery: Text;
        ReqText: Text;
        ResponseText: Text;
        GraphQLUrl: Text;
        ItemNo: Code[20];
    begin
        OrphanCount := 0;

        if not ShopifyShop.Get(ShopCode) then
            exit;

        Token := GetShopifyAccessToken(ShopCode);
        if Token = '' then
            exit;

        ShopUrl := GetShopUrl(ShopifyShop);
        if ShopUrl = '' then
            exit;

        GraphQLUrl := ShopUrl + '/admin/api/2024-01/graphql.json';

        HttpClient.DefaultRequestHeaders().Add('X-Shopify-Access-Token', Token);

        ShpfyProduct.SetRange("Shop Code", ShopCode);
        ShpfyProduct.SetFilter(Id, '<>0');
        if ShpfyProduct.FindSet() then
            repeat
                ItemNo := '';
                if not IsNullGuid(ShpfyProduct."Item SystemId") then
                    if Item.GetBySystemId(ShpfyProduct."Item SystemId") then
                        ItemNo := Item."No.";

                GraphQLQuery := StrSubstNo('{ product(id: "gid://shopify/Product/%1") { id } }', ShpfyProduct.Id);
                Clear(JReqObj);
                JReqObj.Add('query', GraphQLQuery);
                JReqObj.WriteTo(ReqText);

                Clear(HttpContent);
                HttpContent.WriteFrom(ReqText);
                HttpContent.GetHeaders(HttpHeaders);
                HttpHeaders.Remove('Content-Type');
                HttpHeaders.Add('Content-Type', 'application/json');

                if HttpClient.Post(GraphQLUrl, HttpContent, HttpResponseMessage) then
                    if HttpResponseMessage.IsSuccessStatusCode() then begin
                        HttpResponseMessage.Content().ReadAs(ResponseText);
                        if JResponse.ReadFrom(ResponseText) then
                            if JResponse.IsObject() then begin
                                JData := JResponse.AsObject();
                                if JData.Get('data', JProdToken) then
                                    if JProdToken.IsObject() then
                                        if JProdToken.AsObject().Get('product', JProdToken) then begin
                                            if JProdToken.IsValue() then begin
                                                if JProdToken.AsValue().IsNull() then begin
                                                    OrphanCount += 1;
                                                    LogReconcileReason(
                                                        ItemNo,
                                                        '',
                                                        '',
                                                        ShpfyProduct.Id,
                                                        0,
                                                        ShpfyProduct.Title,
                                                        Format(ShpfyProduct.Status),
                                                        Enum::"APSS Shpfy Reconcile Reason"::ORPHAN_MAPPING,
                                                        StrSubstNo('Shopify Product ID %1 no longer exists on Shopify Admin (Orphaned Mapping).', ShpfyProduct.Id)
                                                    );
                                                end;
                                            end else if not JProdToken.IsObject() then begin
                                                OrphanCount += 1;
                                                LogReconcileReason(
                                                    ItemNo,
                                                    '',
                                                    '',
                                                    ShpfyProduct.Id,
                                                    0,
                                                    ShpfyProduct.Title,
                                                    Format(ShpfyProduct.Status),
                                                    Enum::"APSS Shpfy Reconcile Reason"::ORPHAN_MAPPING,
                                                    StrSubstNo('Shopify Product ID %1 no longer exists on Shopify Admin (Orphaned Mapping).', ShpfyProduct.Id)
                                                );
                                            end;
                                        end;
                            end;
                    end;
            until ShpfyProduct.Next() = 0;
    end;

    local procedure LogReconcileReason(
        ItemNo: Code[20];
        VariantCode: Code[20];
        TargetSKU: Text[50];
        ShopifyProductId: BigInteger;
        ShopifyVariantId: BigInteger;
        ShopifyHandle: Text[250];
        ShopifyStatus: Text[50];
        ReasonEnum: Enum "APSS Shpfy Reconcile Reason";
        LogDetails: Text[250]
    )
    var
        ReconcileLog: Record "APSS Shpfy Reconcile Log";
    begin
        ReconcileLog.LogReason(ItemNo, VariantCode, TargetSKU, ShopifyProductId, ShopifyVariantId, ShopifyHandle, ShopifyStatus, ReasonEnum, LogDetails);
    end;

    // Passive safety subscribers — do NOT call Error()
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnBeforeSendCreateShopifyProduct', '', false, false)]
    local procedure OnBeforeSendCreateShopifyProduct(
        ShopifyShop: Record "Shpfy Shop";
        var ShopifyProduct: Record "Shpfy Product";
        var ShopifyVariant: Record "Shpfy Variant";
        var ShpfyTag: Record "Shpfy Tag"
    )
    var
        Item: Record Item;
    begin
        if not IsNullGuid(ShopifyProduct."Item SystemId") then
            if Item.GetBySystemId(ShopifyProduct."Item SystemId") then
                SanitizeItemMarketingText(Item);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Product Events", 'OnBeforeSendAddShopifyProductVariant', '', false, false)]
    local procedure OnBeforeSendAddShopifyProductVariant(
        ShopifyShop: Record "Shpfy Shop";
        var ShopifyVariant: Record "Shpfy Variant"
    )
    begin
        // Passive hook
    end;

    local procedure GetIdOfGId(GIdText: Text): BigInteger
    var
        Pos: Integer;
        SubStr: Text;
        Val: BigInteger;
    begin
        Pos := GIdText.LastIndexOf('/');
        if Pos > 0 then begin
            SubStr := GIdText.Substring(Pos + 1);
            if Evaluate(Val, SubStr) then
                exit(Val);
        end;
        exit(0);
    end;

    local procedure GetJsonString(JObj: JsonObject; PropertyName: Text): Text
    var
        JToken: JsonToken;
    begin
        if JObj.Get(PropertyName, JToken) then
            if JToken.IsValue() then
                exit(JToken.AsValue().AsText());
        exit('');
    end;

    local procedure CheckItemPayloadLimit(Item: Record Item; var ReasonText: Text): Boolean
    var
        EntityText: Codeunit "Entity Text";
        EntityTextScenario: Enum "Entity Text Scenario";
        MarketingText: Text;
    begin
        // 1. Automatically strip embedded Base64 images from Marketing Text before sync
        SanitizeItemMarketingText(Item);

        // 2. Check remaining Marketing Text for extreme length (> 65k chars)
        MarketingText := EntityText.GetText(Database::Item, Item.SystemId, EntityTextScenario::"Marketing Text");
        if MarketingText <> '' then
            if StrLen(MarketingText) > 65000 then begin
                ReasonText := StrSubstNo('Field [Marketing Text] length (%1 chars) exceeds safe limit of 65,000 chars.', StrLen(MarketingText));
                exit(false);
            end;

        // 3. Check Picture count (> 10 images per item)
        if Item.Picture.Count() > 10 then begin
            ReasonText := StrSubstNo('Field [Picture] has %1 images attached, exceeding safe batch limit of 10 images.', Item.Picture.Count());
            exit(false);
        end;

        exit(true);
    end;

    /// <summary>
    /// Strips embedded Base64 images (&lt;img&gt; tags) from Item Marketing Text to prevent payload limit overflow.
    /// Product pictures are preserved and uploaded separately via Item.Picture.
    /// </summary>
    procedure SanitizeItemMarketingText(Item: Record Item)
    var
        ActualItem: Record Item;
        EntityText: Codeunit "Entity Text";
        EntityTextRec: Record "Entity Text";
        EntityTextScenario: Enum "Entity Text Scenario";
        MarketingText: Text;
        CleanHtml: Text;
        TargetGuid: Guid;
        Updated: Boolean;
    begin
        TargetGuid := Item.SystemId;
        if IsNullGuid(TargetGuid) and (Item."No." <> '') then
            if ActualItem.Get(Item."No.") then
                TargetGuid := ActualItem.SystemId;

        if IsNullGuid(TargetGuid) then
            exit;

        MarketingText := EntityText.GetText(Database::Item, TargetGuid, EntityTextScenario::"Marketing Text");
        if MarketingText = '' then
            exit;

        if NeedsSanitization(MarketingText) then begin
            CleanHtml := ConvertMarketingTextToCleanHtml(MarketingText);

            // Primary Key: (Company, "Source Table Id", "Source System Id", Scenario)
            if EntityTextRec.Get(CompanyName(), Database::Item, TargetGuid, EntityTextScenario::"Marketing Text") then begin
                EntityText.UpdateText(EntityTextRec, CleanHtml);
                EntityTextRec.Modify(true);
                Updated := true;
            end else if EntityTextRec.Get('', Database::Item, TargetGuid, EntityTextScenario::"Marketing Text") then begin
                EntityText.UpdateText(EntityTextRec, CleanHtml);
                EntityTextRec.Modify(true);
                Updated := true;
            end else begin
                // Fallback scan across company scopes
                EntityTextRec.Reset();
                EntityTextRec.SetRange("Source Table Id", Database::Item);
                EntityTextRec.SetRange("Source System Id", TargetGuid);
                EntityTextRec.SetRange(Scenario, EntityTextScenario::"Marketing Text");
                if EntityTextRec.FindSet(true) then
                    repeat
                        EntityText.UpdateText(EntityTextRec, CleanHtml);
                        EntityTextRec.Modify(true);
                        Updated := true;
                    until EntityTextRec.Next() = 0;
            end;

            if Updated then begin
                Commit();
                LogSanitizationAudit(Item."No.", StrLen(MarketingText), StrLen(CleanHtml));
            end;
        end;
    end;

    local procedure NeedsSanitization(MarketingText: Text): Boolean
    var
        TabChar: Char;
        Trimmed: Text;
    begin
        TabChar := 9;
        Trimmed := MarketingText.Trim();
        if Trimmed = '' then
            exit(false);

        if Trimmed.Contains('data:image/') or Trimmed.Contains(';base64,') or Trimmed.ToLower().Contains('<img') or
           Trimmed.Contains(Format(TabChar)) or Trimmed.Contains('\t') then
            exit(true);

        // Re-sanitize if table contains empty or spacer <td> cells
        if Trimmed.Contains('<td></td>') or Trimmed.Contains('<td> </td>') or Trimmed.Contains('<td>&nbsp;</td>') or
           Trimmed.Contains('<td><br></td>') or Trimmed.Contains('<td><p></p></td>') then
            exit(true);

        if not (Trimmed.StartsWith('<p') or Trimmed.StartsWith('<div') or Trimmed.StartsWith('<table') or Trimmed.StartsWith('<html') or Trimmed.StartsWith('<body')) then
            exit(true);

        exit(false);
    end;

    procedure CleanMarketingHtmlForGraphQL(InputText: Text): Text
    var
        Clean: Text;
        CRChar: Char;
        LFChar: Char;
        TabChar: Char;
    begin
        if InputText.Trim() = '' then
            exit('');

        CRChar := 13;
        LFChar := 10;
        TabChar := 9;

        // Auto-convert raw plain text or tabbed specs to clean structured HTML before cleaning
        if (not (InputText.Trim().StartsWith('<p') or InputText.Trim().StartsWith('<div') or InputText.Trim().StartsWith('<table') or InputText.Trim().StartsWith('<html') or InputText.Trim().StartsWith('<body') or InputText.Trim().StartsWith('<span'))) or
           (InputText.Contains(Format(TabChar)) or InputText.Contains('\t')) then
            Clean := ConvertMarketingTextToCleanHtml(InputText)
        else
            Clean := InputText;

        // 1. Unescape any double-escaped entities
        Clean := Clean.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '''');

        // 2. Convert all double quotes inside HTML to single quotes so GraphQL string literal isn't broken
        Clean := Clean.Replace('"', '''');

        // 3. Remove all physical newlines and tabs (replace tabs with space, remove \r and \n)
        Clean := Clean.Replace(Format(TabChar), ' ').Replace('\t', ' ');
        Clean := Clean.Replace(Format(CRChar), ' ').Replace(Format(LFChar), ' ');

        // 4. Sanitize and realign any table rows inside the HTML (removes empty spacer cells, enforces 2 columns)
        Clean := SanitizeHtmlTablesInBody(Clean);

        // 5. Collapse multiple spaces
        while Clean.Contains('  ') do
            Clean := Clean.Replace('  ', ' ');

        exit(Clean.Trim());
    end;

    local procedure ConvertMarketingTextToCleanHtml(InputText: Text): Text
    var
        Result: TextBuilder;
        Lines: List of [Text];
        Tokens: List of [Text];
        LineText: Text;
        KeyPart: Text;
        ValPart: Text;
        TrimmedLine: Text;
        InTable: Boolean;
        TabChar: Char;
        LFChar: Char;
        CRChar: Char;
        i: Integer;
        IsFirstLine: Boolean;
    begin
        if InputText.Trim() = '' then
            exit('');

        // Unescape any previously double-escaped entities
        InputText := InputText.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"');
        InputText := RemoveEmbeddedImagesFromHtml(InputText);
        TabChar := 9;
        LFChar := 10;
        CRChar := 13;

        // Split text into lines by LF
        Lines := InputText.Split(Format(LFChar));
        InTable := false;
        IsFirstLine := true;
        Result.Clear();

        foreach LineText in Lines do begin
            TrimmedLine := LineText.Replace(Format(CRChar), '').Trim();

            if TrimmedLine = '' then begin
                if InTable then begin
                    Result.Append('</table>');
                    InTable := false;
                end;
            end else begin
                Tokens := SplitLineByTabs(TrimmedLine);
                if Tokens.Count() >= 2 then begin
                    if not InTable then begin
                        InTable := true;
                        Result.Append('<table style=''width:100%; border-collapse:collapse; margin-top:8px; margin-bottom:12px; font-size:14px;''>');
                    end;

                    KeyPart := Tokens.Get(1).Trim();
                    ValPart := '';
                    for i := 2 to Tokens.Count() do begin
                        if ValPart <> '' then
                            ValPart += ' ';
                        ValPart += Tokens.Get(i).Trim();
                    end;

                    Result.Append('<tr><td style=''padding:6px 10px; border:1px solid #cbd5e1; background-color:#f8fafc; font-weight:600; width:35%;''>' + EscapeHtmlSpecialChars(KeyPart) + '</td>');
                    Result.Append('<td style=''padding:6px 10px; border:1px solid #cbd5e1;''>' + EscapeHtmlSpecialChars(ValPart) + '</td></tr>');
                    IsFirstLine := false;
                end else begin
                    if InTable then begin
                        Result.Append('</table>');
                        InTable := false;
                    end;

                    if IsSectionHeader(TrimmedLine) then
                        Result.Append('<p style=''font-weight:bold; font-size:15px; margin-top:12px; margin-bottom:6px; color:#1e293b;''>' + EscapeHtmlSpecialChars(TrimmedLine) + '</p>')
                    else if TrimmedLine.Contains('<') and TrimmedLine.Contains('>') then
                        Result.Append(TrimmedLine.Replace('"', ''''))
                    else if IsFirstLine then
                        Result.Append('<p style=''font-size:14pt; font-weight:bold; margin-bottom:8px; color:#0f172a;''>' + EscapeHtmlSpecialChars(TrimmedLine) + '</p>')
                    else if TrimmedLine.StartsWith('✔') or TrimmedLine.StartsWith('•') or TrimmedLine.StartsWith('- ') or TrimmedLine.StartsWith('* ') then
                        Result.Append('<p style=''margin:4px 0 4px 12px; line-height:1.5;''>' + EscapeHtmlSpecialChars(TrimmedLine) + '</p>')
                    else
                        Result.Append('<p style=''margin:6px 0; line-height:1.5;''>' + EscapeHtmlSpecialChars(TrimmedLine) + '</p>');

                    IsFirstLine := false;
                end;
            end;
        end;

        if InTable then
            Result.Append('</table>');

        exit(SanitizeHtmlTablesInBody(Result.ToText().Replace(Format(CRChar), '').Replace(Format(LFChar), '').Trim()));
    end;

    local procedure SplitLineByTabs(LineText: Text): List of [Text]
    var
        Tokens: List of [Text];
        RawTokens: List of [Text];
        Tok: Text;
        TabChar: Char;
        Normalized: Text;
    begin
        TabChar := 9;
        Normalized := LineText.Replace('\t', Format(TabChar));
        RawTokens := Normalized.Split(Format(TabChar));
        foreach Tok in RawTokens do
            if Tok.Trim() <> '' then
                Tokens.Add(Tok.Trim());
        exit(Tokens);
    end;

    local procedure SanitizeHtmlTablesInBody(InputHtml: Text): Text
    var
        Result: TextBuilder;
        LowerHtml: Text;
        CurrentPos: Integer;
        TrStart: Integer;
        TrEnd: Integer;
        RowContent: Text;
        CleanRow: Text;
    begin
        if (not InputHtml.ToLower().Contains('<tr')) and (not InputHtml.ToLower().Contains('<table')) then
            exit(InputHtml);

        LowerHtml := InputHtml.ToLower();
        CurrentPos := 1;
        Result.Clear();

        while CurrentPos <= StrLen(InputHtml) do begin
            TrStart := StrPos(CopyStr(LowerHtml, CurrentPos), '<tr');
            if TrStart = 0 then begin
                Result.Append(CopyStr(InputHtml, CurrentPos));
                CurrentPos := StrLen(InputHtml) + 1;
            end else begin
                if TrStart > 1 then
                    Result.Append(CopyStr(InputHtml, CurrentPos, TrStart - 1));

                CurrentPos := CurrentPos + TrStart - 1;
                LowerHtml := InputHtml.ToLower();

                TrEnd := StrPos(CopyStr(LowerHtml, CurrentPos), '</tr>');
                if TrEnd = 0 then begin
                    Result.Append(CopyStr(InputHtml, CurrentPos));
                    CurrentPos := StrLen(InputHtml) + 1;
                end else begin
                    RowContent := CopyStr(InputHtml, CurrentPos, TrEnd + 4);
                    CleanRow := SanitizeSingleTableRow(RowContent);
                    Result.Append(CleanRow);
                    CurrentPos := CurrentPos + TrEnd + 5;
                end;
            end;
            LowerHtml := InputHtml.ToLower();
        end;

        exit(Result.ToText());
    end;

    local procedure SanitizeSingleTableRow(RowHtml: Text): Text
    var
        Cells: List of [Text];
        LowerRow: Text;
        CurrentPos: Integer;
        TdStart: Integer;
        TdCloseTag: Integer;
        TdEnd: Integer;
        CellContent: Text;
        CleanCellText: Text;
        KeyCell: Text;
        ValCell: Text;
        i: Integer;
    begin
        LowerRow := RowHtml.ToLower();
        CurrentPos := 1;

        while CurrentPos <= StrLen(RowHtml) do begin
            TdStart := StrPos(CopyStr(LowerRow, CurrentPos), '<td');
            if TdStart = 0 then
                TdStart := StrPos(CopyStr(LowerRow, CurrentPos), '<th');

            if TdStart = 0 then
                CurrentPos := StrLen(RowHtml) + 1
            else begin
                CurrentPos := CurrentPos + TdStart - 1;
                LowerRow := RowHtml.ToLower();

                TdCloseTag := StrPos(CopyStr(LowerRow, CurrentPos), '>');
                if TdCloseTag = 0 then
                    CurrentPos := StrLen(RowHtml) + 1
                else begin
                    CurrentPos := CurrentPos + TdCloseTag;
                    LowerRow := RowHtml.ToLower();

                    TdEnd := StrPos(CopyStr(LowerRow, CurrentPos), '</td>');
                    if TdEnd = 0 then
                        TdEnd := StrPos(CopyStr(LowerRow, CurrentPos), '</th>');

                    if TdEnd = 0 then begin
                        CellContent := CopyStr(RowHtml, CurrentPos);
                        CurrentPos := StrLen(RowHtml) + 1;
                    end else begin
                        CellContent := CopyStr(RowHtml, CurrentPos, TdEnd - 1);
                        CurrentPos := CurrentPos + TdEnd + 4;
                    end;

                    CleanCellText := StripHtmlTags(CellContent);
                    if CleanCellText <> '' then
                        Cells.Add(CleanCellText);
                end;
            end;
            LowerRow := RowHtml.ToLower();
        end;

        if Cells.Count() = 0 then
            exit('');

        if Cells.Count() = 1 then
            exit('<tr><td colspan=''2'' style=''padding:6px 10px; border:1px solid #cbd5e1; font-weight:600;''>' + Cells.Get(1) + '</td></tr>');

        KeyCell := Cells.Get(1);
        ValCell := '';
        for i := 2 to Cells.Count() do begin
            if ValCell <> '' then
                ValCell += ' ';
            ValCell += Cells.Get(i);
        end;

        exit('<tr><td style=''padding:6px 10px; border:1px solid #cbd5e1; background-color:#f8fafc; font-weight:600; width:35%;''>' + KeyCell + '</td><td style=''padding:6px 10px; border:1px solid #cbd5e1;''>' + ValCell + '</td></tr>');
    end;

    local procedure StripHtmlTags(InputText: Text): Text
    var
        Result: TextBuilder;
        InsideTag: Boolean;
        i: Integer;
        c: Char;
    begin
        InsideTag := false;
        for i := 1 to StrLen(InputText) do begin
            c := InputText[i];
            if c = '<' then
                InsideTag := true
            else if c = '>' then
                InsideTag := false
            else if not InsideTag then
                Result.Append(c);
        end;
        exit(Result.ToText().Replace('&nbsp;', ' ').Replace('  ', ' ').Trim());
    end;

    local procedure IsSectionHeader(LineText: Text): Boolean
    var
        Lower: Text;
    begin
        Lower := LineText.ToLower().Trim();
        exit((Lower = 'item attributes') or (Lower = 'marketing text') or (Lower = 'key features:') or (Lower = 'key features') or
             (Lower = 'features:') or (Lower = 'features') or (Lower = 'specifications:') or (Lower = 'specifications'));
    end;

    local procedure EscapeHtmlSpecialChars(InputStr: Text): Text
    var
        Clean: Text;
    begin
        Clean := InputStr;
        Clean := Clean.Replace('"', '''');
        exit(Clean);
    end;

    local procedure LogSanitizationAudit(ItemNo: Code[20]; OrigLen: Integer; NewLen: Integer)
    var
        DiagLog: Record "APSS Diagnostic Log";
    begin
        Clear(DiagLog);
        DiagLog."Date Time" := CurrentDateTime();
        DiagLog."Session ID" := SessionId();
        DiagLog.Context := 'SanitizeMarketingText';
        DiagLog."Item No." := ItemNo;
        DiagLog."Event Called" := true;
        DiagLog."Calc Succeeded" := true;
        DiagLog.Details := CopyStr(StrSubstNo('Converted raw Marketing Text (%1 chars) to clean HTML table & paragraphs (%2 chars)', OrigLen, NewLen), 1, MaxStrLen(DiagLog.Details));
        DiagLog.Insert(true);
    end;

    /// <summary>
    /// Removes all &lt;img ...&gt; tags and embedded Base64 image data from HTML text.
    /// </summary>
    procedure RemoveEmbeddedImagesFromHtml(InputHtml: Text): Text
    var
        Result: TextBuilder;
        LowerHtml: Text;
        TagStart: Integer;
        TagEnd: Integer;
        CurrentPos: Integer;
        ImgStart: Integer;
    begin
        if InputHtml = '' then
            exit('');

        if not (InputHtml.Contains('<img') or InputHtml.Contains('<IMG') or InputHtml.Contains('<Img') or InputHtml.Contains('data:image/')) then
            exit(InputHtml);

        LowerHtml := InputHtml.ToLower();
        CurrentPos := 1;
        Result.Clear();

        while CurrentPos <= StrLen(InputHtml) do begin
            ImgStart := StrPos(CopyStr(LowerHtml, CurrentPos), '<img');
            if ImgStart = 0 then begin
                Result.Append(CopyStr(InputHtml, CurrentPos));
                CurrentPos := StrLen(InputHtml) + 1;
            end else begin
                TagStart := CurrentPos + ImgStart - 1;
                if TagStart > CurrentPos then
                    Result.Append(CopyStr(InputHtml, CurrentPos, TagStart - CurrentPos));

                TagEnd := StrPos(CopyStr(InputHtml, TagStart), '>');
                if TagEnd = 0 then
                    CurrentPos := StrLen(InputHtml) + 1
                else
                    CurrentPos := TagStart + TagEnd;
            end;
        end;

        exit(Result.ToText().Trim());
    end;

    procedure ApplyMappingsFromReconcileLog(var SelectedLog: Record "APSS Shpfy Reconcile Log"; var SuccessCount: Integer; var FailedCount: Integer; var FailedDetails: Text)
    var
        LogRec: Record "APSS Shpfy Reconcile Log";
        Item: Record Item;
        ShopifyShop: Record "Shpfy Shop";
        ShopifyProduct: Record "Shpfy Product";
        ShopifyVariant: Record "Shpfy Variant";
        ExistingShpfyProduct: Record "Shpfy Product";
        ProductTitleCU: Codeunit "APSS Shopify Product Title";
        FailedBuilder: TextBuilder;
        ShopCode: Code[20];
        BrandName: Text;
        ShopUrl: Text;
    begin
        SuccessCount := 0;
        FailedCount := 0;
        FailedDetails := '';

        if not ShopifyShop.FindFirst() then
            exit;
        ShopCode := ShopifyShop.Code;
        ShopUrl := GetShopUrl(ShopifyShop);

        LogRec.Copy(SelectedLog);
        if LogRec.FindSet(true) then
            repeat
                if LogRec.Reason = Enum::"APSS Shpfy Reconcile Reason"::DUPLICATE_SKU_IN_PRODUCT then begin
                    FailedCount += 1;
                    AppendFailedItem(FailedBuilder, LogRec."Item No.", 'Duplicate SKU in Product');
                end else if (LogRec."Shopify Product Id" = 0) or (LogRec."Item No." = '') then begin
                    FailedCount += 1;
                    AppendFailedItem(FailedBuilder, LogRec."Item No.", 'Missing Product ID / Item No.');
                end else if not Item.Get(LogRec."Item No.") then begin
                    FailedCount += 1;
                    AppendFailedItem(FailedBuilder, LogRec."Item No.", 'Item does not exist in BC');
                end else begin
                    PurgeGhostRecordsForItem(ShopCode, Item.SystemId);

                    ExistingShpfyProduct.SetRange("Item SystemId", Item.SystemId);
                    ExistingShpfyProduct.SetFilter(Id, '<>0&<>%1', LogRec."Shopify Product Id");
                    if not ExistingShpfyProduct.IsEmpty() then begin
                        FailedCount += 1;
                        AppendFailedItem(FailedBuilder, LogRec."Item No.", 'Already mapped to another Product ID');
                    end else begin
                        BrandName := ProductTitleCU.GetBrandName(Item);
                        if not ShopifyProduct.Get(LogRec."Shopify Product Id") then begin
                            ShopifyProduct.Init();
                            ShopifyProduct.Id := LogRec."Shopify Product Id";
                            ShopifyProduct."Shop Code" := ShopCode;
                            ShopifyProduct."Item SystemId" := Item.SystemId;
                            if LogRec."Shopify Handle" <> '' then
                                ShopifyProduct.Title := CopyStr(LogRec."Shopify Handle", 1, MaxStrLen(ShopifyProduct.Title))
                            else
                                ShopifyProduct.Title := CopyStr(Item.Description, 1, MaxStrLen(ShopifyProduct.Title));
                            if BrandName <> '' then
                                ShopifyProduct.Vendor := CopyStr(BrandName, 1, MaxStrLen(ShopifyProduct.Vendor));
                            if Item."Item Category Code" <> '' then
                                ShopifyProduct."Product Type" := CopyStr(Item."Item Category Code", 1, MaxStrLen(ShopifyProduct."Product Type"));
                            ShopifyProduct."SEO Title" := CopyStr(ShopifyProduct.Title, 1, 70);
                            ShopifyProduct."SEO Description" := CopyStr(Item.Description, 1, 160);
                            ShopifyProduct."Created At" := CurrentDateTime;
                            ShopifyProduct."Updated At" := CurrentDateTime;
                            if (ShopUrl <> '') and (LogRec."Shopify Handle" <> '') then
                                ShopifyProduct.URL := CopyStr(ShopUrl + '/products/' + LogRec."Shopify Handle", 1, MaxStrLen(ShopifyProduct.URL));
                            ShopifyProduct.Insert(false);
                        end else begin
                            ShopifyProduct."Item SystemId" := Item.SystemId;
                            ShopifyProduct."Shop Code" := ShopCode;
                            if ShopifyProduct.Title = '' then begin
                                if LogRec."Shopify Handle" <> '' then
                                    ShopifyProduct.Title := CopyStr(LogRec."Shopify Handle", 1, MaxStrLen(ShopifyProduct.Title))
                                else
                                    ShopifyProduct.Title := CopyStr(Item.Description, 1, MaxStrLen(ShopifyProduct.Title));
                            end;
                            if (ShopifyProduct.Vendor = '') and (BrandName <> '') then
                                ShopifyProduct.Vendor := CopyStr(BrandName, 1, MaxStrLen(ShopifyProduct.Vendor));
                            if (ShopifyProduct."Product Type" = '') and (Item."Item Category Code" <> '') then
                                ShopifyProduct."Product Type" := CopyStr(Item."Item Category Code", 1, MaxStrLen(ShopifyProduct."Product Type"));
                            if ShopifyProduct."SEO Title" = '' then
                                ShopifyProduct."SEO Title" := CopyStr(ShopifyProduct.Title, 1, 70);
                            if ShopifyProduct."SEO Description" = '' then
                                ShopifyProduct."SEO Description" := CopyStr(Item.Description, 1, 160);
                            ShopifyProduct."Updated At" := CurrentDateTime;
                            if (ShopifyProduct.URL = '') and (ShopUrl <> '') and (LogRec."Shopify Handle" <> '') then
                                ShopifyProduct.URL := CopyStr(ShopUrl + '/products/' + LogRec."Shopify Handle", 1, MaxStrLen(ShopifyProduct.URL));
                            ShopifyProduct.Modify(false);
                        end;

                        if LogRec."Shopify Variant Id" <> 0 then begin
                            if not ShopifyVariant.Get(LogRec."Shopify Variant Id") then begin
                                ShopifyVariant.Init();
                                ShopifyVariant.Id := LogRec."Shopify Variant Id";
                                ShopifyVariant."Product Id" := LogRec."Shopify Product Id";
                                ShopifyVariant."Shop Code" := ShopCode;
                                ShopifyVariant."Item SystemId" := Item.SystemId;
                                ShopifyVariant."Item No." := Item."No.";
                                ShopifyVariant.SKU := CopyStr(LogRec.SKU, 1, MaxStrLen(ShopifyVariant.SKU));
                                ShopifyVariant.Insert(false);
                            end else begin
                                ShopifyVariant."Product Id" := LogRec."Shopify Product Id";
                                ShopifyVariant."Shop Code" := ShopCode;
                                ShopifyVariant."Item SystemId" := Item.SystemId;
                                ShopifyVariant."Item No." := Item."No.";
                                ShopifyVariant.SKU := CopyStr(LogRec.SKU, 1, MaxStrLen(ShopifyVariant.SKU));
                                ShopifyVariant.Modify(false);
                            end;
                        end;

                        LogRec.Resolved := true;
                        LogRec.Selected := false;
                        LogRec.Modify(false);
                        SuccessCount += 1;
                    end;
                end;
            until LogRec.Next() = 0;

        FailedDetails := FailedBuilder.ToText();
    end;

    local procedure AppendFailedItem(var Builder: TextBuilder; ItemNo: Code[20]; ReasonText: Text)
    begin
        if Builder.Length() > 0 then
            Builder.Append('; ');
        if ItemNo <> '' then
            Builder.Append(ItemNo + ': ' + ReasonText)
        else
            Builder.Append(ReasonText);
    end;
}

