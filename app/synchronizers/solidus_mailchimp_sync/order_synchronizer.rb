module SolidusMailchimpSync
  # Syncs solidus orders to mailchimp Carts and Orders, adding/deleting
  # as cart status changes.
  class OrderSynchronizer < BaseSynchronizer
    self.serializer_class_name = "::SolidusMailchimpSync::OrderSerializer"
    # We update on all state changes, even though some might not really
    # require a mailchimp sync, it just depends on what we're serializing.
    # Also, when solidus sets completed_at, it seems not to trigger
    # an after_commit, so we can't catch transition to complete that way.
    #
    # We update on changes to any totals, but removing a line item and adding
    # another with the exact same price won't trigger total changes, so
    # we also trap all line item changes on a LineItem decorator.
    # This might result in some superfluous syncs.
    self.synced_attributes = %w{state total tax_total}

    class_attribute :line_item_serializer_class_name
    self.line_item_serializer_class_name = "::SolidusMailchimpSync::LineItemSerializer"

    class_attribute :only_auto_sync_if
    # By default only sync if we can provide a customer ID. This can be overridden
    # to provide alternative logic.
    self.only_auto_sync_if = lambda { |o| o.user.present? && o.user.send(UserSynchronizer.email_address_attribute).present? }

    def can_sync?
       only_auto_sync_if.call(model) && super
    end

    def path
      if order_complete?
        order_path
      else
        cart_path
      end
    end

    def create_path
      if order_complete?
        create_order_path
      else
        create_cart_path
      end
    end

    def sync
      # Can't sync an empty cart to mailchimp, delete the cart/order if
      # we've previously synced, and bail out of this sync.
      if model.line_items.empty?
        return delete(path, ignore_404: true)
      end

      # if it's a completed order, delete any previous synced _cart_ version
      # of this order, if one is present. There should be no Mailchimp 'cart',
      # only a mailchimp 'order' now.
      #byebug
      if order_complete?
        delete(cart_path, ignore_404: true)
      end

      post_or_patch(post_path: create_path, patch_path: path)
      check_and_delete_line_items
    rescue SolidusMailchimpSync::Error => e
      tries ||= 0 ; tries += 1
      if tries <= 1 && user_not_synced_error?(e) && model.user
        SolidusMailchimpSync::UserSynchronizer.new(model.user).sync
        retry
      else
        raise e
      end
    end

    def check_and_delete_line_items
      # TODO: we perhaps need a LineItemSynchronizer to handle this formally.
      return if order_complete?

      mailchimp_line_item_ids = get.with_indifferent_access[:lines].map { |line| line[:id] }
      existing_line_item_ids = serializer.as_json.with_indifferent_access[:lines].map { |line| line[:id] }
      line_item_ids_to_delete = mailchimp_line_item_ids - existing_line_item_ids
      line_item_ids_to_delete.each do |line_item_id|
        delete("#{cart_path}/lines/#{CGI.escape line_item_id}", ignore_404: true)
      end
    end

    def order_complete?
      # Yes, somehow solidus can sometimes, temporarily, in our after commit hook
      # have state==complete set, but not completed_at
      model.completed? || model.state == "complete"
    end

    def post_or_patch(post_path:, patch_path:)
      post(post_path)
    rescue SolidusMailchimpSync::Error => e
      if e.status == 400 && e.detail =~ /already exists/
        patch(patch_path)
      else
        raise e
      end
    end

    def user_not_synced_error?(e)
      e.status == 400 &&
        e.response_hash["errors"].present? &&
        e.response_hash["errors"].any? { |h| %w{customer.email_address customer.opt_in_status}.include? h["field"] }
    end

    def cart_path
      "/carts/#{CGI.escape mailchimp_id}"
    end

    def create_cart_path
      "/carts"
    end

    def order_path
      "/orders/#{CGI.escape mailchimp_id}"
    end

    def create_order_path
      "/orders"
    end

    def mailchimp_id
      self.class.order_id(model)
    end

    def self.order_id(order)
      serializer_class_name.constantize.new(order).as_json[:id]
    end
  end
end
