require 'active_merchant/billing/gateways/onlinepayments'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CawlGateway < OnlinePaymentsGateway
      def self.display_name
        'CAWL'
      end

      def self.homepage_url
        'https://docs.ecommerce.cawl-solutions.fr/en/'
      end

      def self.default_currency
        'EUR'
      end

      def self.test_url
        'https://payment.preprod.ca.cawl-solutions.fr'
      end

      def self.live_url
        'https://payment.ca.cawl-solutions.fr'
      end

      # Set the class attributes
      self.display_name = display_name
      self.homepage_url = homepage_url
      self.default_currency = default_currency
      self.test_url = test_url
      self.live_url = live_url
    end
  end
end 