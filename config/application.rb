require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module AccountingDemo
  class Application < Rails::Application
    config.load_defaults 7.0

    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue } }
  end
end
