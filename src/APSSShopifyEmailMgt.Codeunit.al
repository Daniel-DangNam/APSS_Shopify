namespace APSS.Shopify;

using Microsoft.Integration.Shopify;
using System.Email;
using Microsoft.Inventory.Item;

codeunit 90303 "APSS Shopify Email Mgt."
{
    procedure SendSyncNotification(ShopCode: Code[20]; var SelectedItem: Record Item temporary; NewCount: Integer; ModifiedCount: Integer)
    var
        ShpfyShop: Record "Shpfy Shop";
        EmailMessage: Codeunit "Email Message";
        Email: Codeunit Email;
        RecipientList: List of [Text];
        Subject: Text;
        Body: Text;
    begin
        if ShopCode = '' then
            exit;

        if not ShpfyShop.Get(ShopCode) then
            exit;

        if ShpfyShop."APSS Procurement Email" = '' then
            exit;

        Subject := StrSubstNo('Shopify Sync Notification - Shop %1 (%2 New, %3 Modified)', ShopCode, NewCount, ModifiedCount);
        Body := BuildSuccessHtmlBody(ShopCode, SelectedItem, NewCount, ModifiedCount);

        RecipientList.Add(ShpfyShop."APSS Procurement Email");
        EmailMessage.Create(RecipientList, Subject, Body, true);

        if not Email.Send(EmailMessage, Enum::"Email Scenario"::"APSS Shopify Procurement") then
            Session.LogMessage('0000APSS', 'Failed to send Shopify sync email notification.', Verbosity::Warning, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, 'Category', 'APSS Shopify');
    end;

    procedure SendErrorNotification(ShopCode: Code[20]; var SelectedItem: Record Item temporary; ErrorTitle: Text; ErrorDetails: Text)
    var
        ShpfyShop: Record "Shpfy Shop";
        EmailMessage: Codeunit "Email Message";
        Email: Codeunit Email;
        RecipientList: List of [Text];
        Subject: Text;
        Body: Text;
    begin
        if ShopCode = '' then
            exit;

        if not ShpfyShop.Get(ShopCode) then
            exit;

        if ShpfyShop."APSS Procurement Email" = '' then
            exit;

        Subject := StrSubstNo('Shopify Sync ERROR Notification - Shop %1', ShopCode);
        Body := BuildErrorHtmlBody(ShopCode, SelectedItem, ErrorTitle, ErrorDetails);

        RecipientList.Add(ShpfyShop."APSS Procurement Email");
        EmailMessage.Create(RecipientList, Subject, Body, true);

        if not Email.Send(EmailMessage, Enum::"Email Scenario"::"APSS Shopify Procurement") then
            Session.LogMessage('0000APSS', 'Failed to send Shopify sync error email notification.', Verbosity::Warning, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, 'Category', 'APSS Shopify');
    end;

    local procedure BuildSuccessHtmlBody(ShopCode: Code[20]; var SelectedItem: Record Item temporary; NewCount: Integer; ModifiedCount: Integer): Text
    var
        ShopifyReadinessMgt: Codeunit "APSS Shopify Readiness Mgt.";
        Status: Enum "APSS Shopify Item Sync Status";
        BodyBuilder: TextBuilder;
        TableRowsBuilder: TextBuilder;
        StatusBadgeHtml: Text;
        ItemNote: Text;
        HasItemWarning: Boolean;
        TotalWarnings: Integer;
        HeaderColor: Text;
        HeaderTitle: Text;
    begin
        HeaderColor := 'linear-gradient(135deg, #008060 0%, #004c3f 100%)';
        HeaderTitle := 'Shopify Product Sync Notification';

        if SelectedItem.FindSet() then
            repeat
                HasItemWarning := false;
                Status := ShopifyReadinessMgt.GetItemSyncStatus(SelectedItem);
                ItemNote := GetItemSyncNote(SelectedItem, ShopCode, HasItemWarning);

                if HasItemWarning then begin
                    TotalWarnings += 1;
                    StatusBadgeHtml := '<span style="background-color: #fee2e2; color: #991b1b; padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: 600;">REQUIRES ATTENTION</span>';
                end else if Status = Enum::"APSS Shopify Item Sync Status"::"New Ready" then
                    StatusBadgeHtml := '<span style="background-color: #dcfce7; color: #166534; padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: 600;">NEW CREATED</span>'
                else if Status = Enum::"APSS Shopify Item Sync Status"::"Modified Ready" then
                    StatusBadgeHtml := '<span style="background-color: #fef3c7; color: #92400e; padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: 600;">MODIFIED UPDATED</span>'
                else
                    StatusBadgeHtml := '<span style="background-color: #f1f5f9; color: #475569; padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: 600;">SYNCED</span>';

                TableRowsBuilder.Append('<tr>');
                TableRowsBuilder.Append(StrSubstNo('<td style="padding: 10px 12px; border-bottom: 1px solid #e2e8f0; font-weight: 600;">%1</td>', SelectedItem."No."));
                TableRowsBuilder.Append(StrSubstNo('<td style="padding: 10px 12px; border-bottom: 1px solid #e2e8f0;">%1</td>', SelectedItem.Description));
                TableRowsBuilder.Append(StrSubstNo('<td style="padding: 10px 12px; border-bottom: 1px solid #e2e8f0;">%1</td>', StatusBadgeHtml));
                TableRowsBuilder.Append(StrSubstNo('<td style="padding: 10px 12px; border-bottom: 1px solid #e2e8f0; font-size: 12px; color: #475569;">%1</td>', ItemNote));
                TableRowsBuilder.Append('</tr>');
            until SelectedItem.Next() = 0;

        if TotalWarnings > 0 then begin
            HeaderColor := 'linear-gradient(135deg, #d97706 0%, #92400e 100%)';
            HeaderTitle := StrSubstNo('Shopify Product Sync Completed (%1 Warnings / Items to Check)', TotalWarnings);
        end;

        BodyBuilder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head>');
        BodyBuilder.Append('<body style="font-family: ''Segoe UI'', Tahoma, Geneva, Verdana, sans-serif; color: #333333; margin: 0; padding: 20px; background-color: #f4f6f9;">');
        BodyBuilder.Append('<div style="max-width: 750px; margin: 0 auto; background: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.05); border: 1px solid #e1e5eb;">');
        
        BodyBuilder.Append(StrSubstNo('<div style="background: %1; padding: 22px 25px; color: #ffffff;">', HeaderColor));
        BodyBuilder.Append(StrSubstNo('<h2 style="margin: 0; font-size: 20px; font-weight: 600;">%1</h2>', HeaderTitle));
        BodyBuilder.Append('</div>');

        BodyBuilder.Append('<div style="padding: 25px;">');
        BodyBuilder.Append(StrSubstNo('<p style="margin-top: 0;">Hello Procurement Team,</p><p>The product sync action to Shopify shop <b>%1</b> has completed. Here is the detailed item-by-item status breakdown:</p>', ShopCode));
        
        BodyBuilder.Append('<table style="width: 100%; margin-bottom: 25px; border-collapse: collapse;"><tr>');
        BodyBuilder.Append(StrSubstNo('<td style="width: 48%%; background: #f8fafc; padding: 15px; border-radius: 6px; border-left: 4px solid #008060;"><div style="font-size: 24px; font-weight: bold; color: #008060;">%1</div><div style="font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 2px;">New Items Created</div></td>', NewCount));
        BodyBuilder.Append('<td style="width: 4%%;"></td>');
        BodyBuilder.Append(StrSubstNo('<td style="width: 48%%; background: #f8fafc; padding: 15px; border-radius: 6px; border-left: 4px solid #d97706;"><div style="font-size: 24px; font-weight: bold; color: #d97706;">%1</div><div style="font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 2px;">Modified Items Updated</div></td>', ModifiedCount));
        BodyBuilder.Append('</tr></table>');

        BodyBuilder.Append('<h3 style="font-size: 15px; color: #1e293b; margin-bottom: 12px; border-bottom: 2px solid #f1f5f9; padding-bottom: 8px;">Detailed Item Status Breakdown</h3>');
        BodyBuilder.Append('<table style="width: 100%; border-collapse: collapse; font-size: 13px;">');
        BodyBuilder.Append('<thead><tr style="background-color: #f1f5f9; color: #475569; text-align: left;">');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #e2e8f0; width: 15%;">Item No.</th>');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #e2e8f0; width: 35%;">Description</th>');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #e2e8f0; width: 20%;">Sync Action</th>');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #e2e8f0; width: 30%;">Status Notes / Details</th>');
        BodyBuilder.Append('</tr></thead>');
        BodyBuilder.Append('<tbody>');
        BodyBuilder.Append(TableRowsBuilder.ToText());
        BodyBuilder.Append('</tbody></table>');

        BodyBuilder.Append('</div>');

        BodyBuilder.Append('<div style="padding: 15px 25px; background: #f8fafc; border-top: 1px solid #e1e5eb; font-size: 12px; color: #94a3b8; text-align: center;">');
        BodyBuilder.Append('Automated email notification sent by Business Central APSS Shopify Integration.');
        BodyBuilder.Append('</div></div></body></html>');

        exit(BodyBuilder.ToText());
    end;

    local procedure GetItemSyncNote(Item: Record Item; ShopCode: Code[20]; var HasWarning: Boolean): Text
    var
        ShpfyProduct: Record "Shpfy Product";
        DiagLog: Record "APSS Diagnostic Log";
        NoteBuilder: TextBuilder;
    begin
        ShpfyProduct.SetRange("Shop Code", ShopCode);
        ShpfyProduct.SetRange("Item SystemId", Item.SystemId);
        if ShpfyProduct.IsEmpty() then begin
            HasWarning := true;
            exit('⚠️ Product not linked on Shopify yet. Please check Shopify Log Entries.');
        end;

        // Check Diagnostic Log for recent errors on this item
        DiagLog.SetRange("Item No.", Item."No.");
        DiagLog.SetRange("Shop Code", ShopCode);
        DiagLog.SetRange("Calc Succeeded", false);
        if DiagLog.FindFirst() then begin
            HasWarning := true;
            NoteBuilder.Append('⚠️ Price Calc Error: ' + DiagLog."Error Text");
        end;

        if Format(Item."Lead Time Calculation") = '' then begin
            if NoteBuilder.Length() > 0 then NoteBuilder.Append('; ');
            NoteBuilder.Append('Lead Time empty');
        end;

        if NoteBuilder.Length() = 0 then
            NoteBuilder.Append('OK (Metafields & Images synced)');

        exit(NoteBuilder.ToText());
    end;

    local procedure BuildErrorHtmlBody(ShopCode: Code[20]; var SelectedItem: Record Item temporary; ErrorTitle: Text; ErrorDetails: Text): Text
    var
        BodyBuilder: TextBuilder;
        TableRowsBuilder: TextBuilder;
    begin
        if SelectedItem.FindSet() then
            repeat
                TableRowsBuilder.Append('<tr>');
                TableRowsBuilder.Append(StrSubstNo('<td style="padding: 10px 12px; border-bottom: 1px solid #fee2e2; font-weight: 600;">%1</td>', SelectedItem."No."));
                TableRowsBuilder.Append(StrSubstNo('<td style="padding: 10px 12px; border-bottom: 1px solid #fee2e2;">%1</td>', SelectedItem.Description));
                TableRowsBuilder.Append('<td style="padding: 10px 12px; border-bottom: 1px solid #fee2e2;"><span style="background-color: #fee2e2; color: #991b1b; padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: 600;">FAILED</span></td>');
                TableRowsBuilder.Append('</tr>');
            until SelectedItem.Next() = 0;

        BodyBuilder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head>');
        BodyBuilder.Append('<body style="font-family: ''Segoe UI'', Tahoma, Geneva, Verdana, sans-serif; color: #333333; margin: 0; padding: 20px; background-color: #fff5f5;">');
        BodyBuilder.Append('<div style="max-width: 650px; margin: 0 auto; background: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.05); border: 1px solid #fecaca;">');
        
        // Red Header
        BodyBuilder.Append('<div style="background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%); padding: 22px 25px; color: #ffffff;">');
        BodyBuilder.Append('<h2 style="margin: 0; font-size: 20px; font-weight: 600;">Shopify Sync ERROR Notification</h2>');
        BodyBuilder.Append('</div>');

        // Content
        BodyBuilder.Append('<div style="padding: 25px;">');
        BodyBuilder.Append(StrSubstNo('<p style="margin-top: 0;">Hello Procurement Team,</p><p>An error occurred while synchronizing products to Shopify shop <b>%1</b>. Below are the details:</p>', ShopCode));
        
        // Error Card Alert
        BodyBuilder.Append('<div style="background: #fef2f2; border: 1px solid #fca5a5; border-left: 5px solid #dc2626; padding: 15px; border-radius: 6px; margin-bottom: 25px;">');
        BodyBuilder.Append(StrSubstNo('<div style="font-weight: bold; color: #991b1b; font-size: 15px; margin-bottom: 5px;">%1</div>', ErrorTitle));
        BodyBuilder.Append(StrSubstNo('<div style="font-size: 13px; color: #7f1d1d; font-family: monospace; white-space: pre-wrap;">%1</div>', ErrorDetails));
        BodyBuilder.Append('</div>');

        // Affected Items Table
        BodyBuilder.Append('<h3 style="font-size: 15px; color: #991b1b; margin-bottom: 12px; border-bottom: 2px solid #fee2e2; padding-bottom: 8px;">Affected Products List</h3>');
        BodyBuilder.Append('<table style="width: 100%; border-collapse: collapse; font-size: 13px;">');
        BodyBuilder.Append('<thead><tr style="background-color: #fef2f2; color: #991b1b; text-align: left;">');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #fca5a5;">Item No.</th>');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #fca5a5;">Description</th>');
        BodyBuilder.Append('<th style="padding: 10px 12px; font-weight: 600; border-bottom: 2px solid #fca5a5;">Status</th>');
        BodyBuilder.Append('</tr></thead>');
        BodyBuilder.Append('<tbody>');
        BodyBuilder.Append(TableRowsBuilder.ToText());
        BodyBuilder.Append('</tbody></table>');

        BodyBuilder.Append('</div>');

        // Footer
        BodyBuilder.Append('<div style="padding: 15px 25px; background: #fff5f5; border-top: 1px solid #fecaca; font-size: 12px; color: #991b1b; text-align: center;">');
        BodyBuilder.Append('Automated error report sent by Business Central APSS Shopify Integration.');
        BodyBuilder.Append('</div></div></body></html>');

        exit(BodyBuilder.ToText());
    end;
}
