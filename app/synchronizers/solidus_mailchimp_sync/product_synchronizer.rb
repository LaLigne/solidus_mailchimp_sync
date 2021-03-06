module SolidusMailchimpSync
  class ProductSynchronizer < BaseSynchronizer
    self.serializer_class_name = "::SolidusMailchimpSync::ProductSerializer"
    self.synced_attributes = %w{name description slug available_on}

    # Since Mailchimp API 3.0 doesn't let us update products, important to wait
    # until product is really ready to sync it the first time.
    class_attribute :only_auto_sync_if
    self.only_auto_sync_if = lambda { |p| p.available? }

    def can_sync?
       only_auto_sync_if.call(model) && super
    end

    def sync
      post
    rescue SolidusMailchimpSync::Error => e
      if e.status == 400 && e.detail =~ /already exists/
        patch
      else
        raise e
      end
    end

    def path
      "/products/#{CGI.escape mailchimp_id}"
    end

    def create_path
      "/products"
    end

    def mailchimp_id
      self.class.product_id(model)
    end

    def self.product_id(product)
      serializer_class_name.constantize.new(product).as_json[:id]
    end

    def sync_all_variants
      model.variants_including_master.collect do |variant|
        VariantSynchronizer.new(variant).sync
      end
    end
  end
end
