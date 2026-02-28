# frozen_string_literal: true

module Recurable
  class Railtie < Rails::Railtie
    initializer 'recurable.i18n' do
      I18n.load_path += Dir["#{__dir__}/../../config/locales/*.yml"]
    end
  end
end
