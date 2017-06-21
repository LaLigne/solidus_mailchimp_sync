Spree::Variant.class_eval do
  after_commit :mailchimp_sync

  private
  def mailchimp_sync
    if product && !product.deleted?
      SolidusMailchimpSync::VariantSynchronizer.new(self).auto_sync
    end
  end
end
