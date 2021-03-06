namespace :solidus_mailchimp_sync do
  desc "Create a Mailchimp Store. ENV LIST_ID param is required"
  task create_mailchimp_store: :environment do
    unless ENV["LIST_ID"].present?
      raise ArgumentError, "LIST_ID env arg is required. Your mailchimp Listserv ID."
    end

    response = SolidusMailchimpSync::Mailchimp.request(:post, "/ecommerce/stores", body: {
      list_id: ENV["LIST_ID"],
      id: ENV["NEW_STORE_ID"] || (Spree::Store.default.name || "solidus").parameterize,
      name: Spree::Store.default.name || "Solidus",
      currency_code: Spree::Store.default.default_currency || 'USD'
    })
    store_id = response["id"]

    raise TypeError, "Unexpected response from Mailchimp, can't find created store id" unless store_id.present?

    puts "\nNew Mailchimp Store created with id: `#{store_id}`"
    puts
    puts "You probably want to add to your ./config/initializers/solidus_mailchimp_sync.rb:"
    puts
    puts "   SolidusMailchimpSync.store_id='#{store_id}'"
    puts
  end

  desc "enable is_syncing mode"
  task :enable_is_syncing => :environment do
    puts "Enabling is_syncing mode"
    response = SolidusMailchimpSync::Mailchimp.request(:patch, "/ecommerce/stores/#{CGI.escape ENV['MAILCHIMP_STORE_ID']}", body: {
      is_syncing: true,
    })
    if response['is_syncing']
      puts "is_syncing mode was enabled successfully."
    else
      puts "is_syncing mode was not enabled."
    end
  end

  desc "disable is_syncing mode"
  task :disable_is_syncing => :environment do
    puts "Disable is_syncing mode"
    response = SolidusMailchimpSync::Mailchimp.request(:patch, "/ecommerce/stores/#{CGI.escape ENV['MAILCHIMP_STORE_ID']}", body: {
      is_syncing: false,
    })
    if !response['is_syncing']
      puts "is_syncing mode was disabled successfully."
    else
      puts "is_syncing mode was not disabled."
    end
  end

  desc "sync ALL data to mailchimp"
  task :bulk_sync => :environment do
    require 'ruby-progressbar'

    progress_format = '%t %c of %C |%B| %e'

    puts "\nSyncing Users, Products, and Orders to mailchimp, this could take a while...\n\n"

    if Spree.user_class
      user_count = Spree.user_class.count
      progress_bar = ProgressBar.create(total: user_count, format: progress_format, title: Spree.user_class.name.pluralize)
      Spree.user_class.find_each do |user|
        begin
          synchronizer = SolidusMailchimpSync::UserSynchronizer.new(user)
          synchronizer.sync if synchronizer.can_sync?
        rescue SolidusMailchimpSync::Error => e
          # just so we know what user failed.
          puts user.inspect
          raise e
        end
        progress_bar.increment
      end
      progress_bar.finish
    end

    product_count = Spree::Product.count
    progress_bar = ProgressBar.create(total: product_count, format: progress_format, title: "Spree::Products")
    Spree::Product.find_each do |product|
      begin
        synchronizer = SolidusMailchimpSync::ProductSynchronizer.new(product)
        synchronizer.sync if synchronizer.can_sync?
      rescue SolidusMailchimpSync::Error => e
        puts product.inspect
        raise e
      end
      progress_bar.increment
    end
    progress_bar.finish

    # Exclude orders which have variants that no longer exist
    exclude_order_ids = Spree::LineItem.where(variant_id: Spree::Variant.deleted).pluck(:order_id).uniq

    order_arel = Spree::Order.complete.where('id NOT IN (?)', exclude_order_ids)

    progress_bar = ProgressBar.create(total: order_arel.count, format: progress_format, title: "Completed Spree::Orders")

    order_arel.find_each do |order|
      begin
        synchronizer = SolidusMailchimpSync::OrderSynchronizer.new(order)
        synchronizer.sync if synchronizer.can_sync?
      rescue SolidusMailchimpSync::Error => e
        puts order.inspect
        raise e
      end
      progress_bar.increment
    end
    progress_bar.finish
  end
end
