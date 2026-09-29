namespace APSS.Shopify;

using Microsoft.Integration.Shopify;

reportextension 90301 "APSS Sync Products" extends "Shpfy Sync Products"
{
    trigger OnPostReport()
    var
        SyncNotification: Notification;
    begin
        SyncNotification.Id := CreateGuid();
        SyncNotification.Message := 'Shopify Product Sync has completed.';
        SyncNotification.Scope := NotificationScope::LocalScope;
        SyncNotification.Send();
    end;
}
