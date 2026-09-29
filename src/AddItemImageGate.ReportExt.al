reportextension 90300 "APSS Add Item Image Gate" extends "Shpfy Add Item to Shopify"
{
    dataset
    {
        modify(Item)
        {
            trigger OnBeforePreDataItem()
            var
                CandidateItem: Record Item;
                ProductTitleCU: Codeunit "APSS Shopify Product Title";
                FilterBuilder: TextBuilder;
                IsEligible: Boolean;
            begin
                // Copy the current Item filters applied to the report
                CandidateItem.CopyFilters(Item);

                // Evaluate candidate items: APSS Approved = true AND Picture.Count() > 0 AND Required Master Data
                if CandidateItem.FindSet() then begin
                    repeat
                        IsEligible := ProductTitleCU.IsItemApproved(CandidateItem) and
                                      (CandidateItem.Picture.Count() > 0) and
                                      (ProductTitleCU.GetBrandName(CandidateItem) <> '') and
                                      (CandidateItem.Description.Trim() <> '') and
                                      (CandidateItem."Base Unit of Measure" <> '');

                        if IsEligible then begin
                            if FilterBuilder.Length() > 0 then
                                FilterBuilder.Append('|');
                            FilterBuilder.Append('''' + CandidateItem."No." + '''');
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
