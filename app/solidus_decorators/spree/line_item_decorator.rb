Spree::LineItem.class_eval do
  after_commit :mailchimp_sync

  def mailchimp_sync
    if order && !order.destroyed?
      # If a LineItem changes, tell the order to Sync for sure.
      SolidusMailchimpSync::OrderSynchronizer.new(order).auto_sync(force: true)
    end
  end
end
