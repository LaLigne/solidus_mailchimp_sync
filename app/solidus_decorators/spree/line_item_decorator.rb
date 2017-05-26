Spree::LineItem.class_eval do
  after_commit :mailchimp_sync

  def mailchimp_sync
    unless order.deleted?
      # If a LineItem changes, tell the order to Sync for sure.
      SolidusMailchimpSync::OrderSynchronizer.new(order).auto_sync(force: true)
    end
  end
end
