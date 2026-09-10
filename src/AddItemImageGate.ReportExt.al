reportextension 90300 "APSS Add Item Image Gate" extends "Shpfy Add Item to Shopify"
{
    dataset
    {
        modify(Item)
        {
            trigger OnBeforePreDataItem()
            var
                CandidateItem: Record Item;
                FilterBuilder: TextBuilder;
            begin
                // Copy the current Item filters applied to the report
                CandidateItem.CopyFilters(Item);

                // Evaluate candidate items and build a filter containing ONLY Item No. values where Picture.Count() > 0
                if CandidateItem.FindSet() then begin
                    repeat
                        if CandidateItem.Picture.Count() > 0 then begin
                            if FilterBuilder.Length() > 0 then
                                FilterBuilder.Append('|');
                            FilterBuilder.Append(CandidateItem."No.");
                        end;
                    until CandidateItem.Next() = 0;
                end;

                // Apply that filter to the report's Item dataitem.
                // If there are no valid image Items, apply a guaranteed no-match filter.
                if FilterBuilder.Length() > 0 then
                    Item.SetFilter("No.", FilterBuilder.ToText())
                else
                    Item.SetFilter("No.", '%1', 'APSS_NO_IMAGE_MATCH'); // Guaranteed no-match
            end;
        }
    }
}
