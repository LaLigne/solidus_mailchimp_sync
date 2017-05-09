module SolidusMailchimpSync
  class VariantSynchronizer < BaseSynchronizer
    self.serializer_class_name = "::SolidusMailchimpSync::VariantSerializer"
    # Price updates are caught from after commit on Spree::Price
    self.synced_attributes = %w{id sku}

    def sync
      put
    rescue SolidusMailchimpSync::Error => e
      tries ||= 0 ; tries += 1
      if tries <= 1 && e.status == 400 && e.title == 'Parent Product Does Not Exist'
        ProductSynchronizer.new(model.product).sync
        retry
      else
        raise e
      end
    end

    def path
      "/products/#{CGI.escape ProductSynchronizer.product_id(model.product)}/variants/#{CGI.escape mailchimp_id}"
    end

    def mailchimp_id
      self.class.variant_id(model)
    end

    def self.variant_id(variant)
      serializer_class_name.constantize.new(variant).as_json[:id]
    end
  end
end
