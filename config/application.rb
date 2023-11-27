require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Workflow
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # 時區設定
    config.time_zone = "Taipei"
    config.active_record.default_timezone = :local

    # 語系檔設定
    config.i18n.default_locale = "zh-TW"
    config.i18n.available_locales = [:"zh-TW"]
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
  
    # 自動載入資料匣裡的檔案
    config.autoload_paths += ["#{config.root}/lib"]

   # 將 rails generator 預設建立的檔案設為不自動生成
    config.generators do |g|
      g.stylesheets     false
      g.javascripts     false
      g.helper          false
    end
  end
end
