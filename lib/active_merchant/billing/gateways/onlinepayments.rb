require 'onlinepayments/sdk/factory'
require 'onlinepayments/sdk/domain/create_payment_request'
require 'onlinepayments/sdk/domain/card_payment_method_specific_input'
require 'onlinepayments/sdk/domain/card'
require 'onlinepayments/sdk/domain/order'
require 'onlinepayments/sdk/domain/amount_of_money'
require 'onlinepayments/sdk/domain/customer'
require 'onlinepayments/sdk/domain/personal_information'
require 'onlinepayments/sdk/domain/personal_name'
require 'onlinepayments/sdk/domain/address'
require 'onlinepayments/sdk/domain/contact_details'
require 'onlinepayments/sdk/domain/order_references'
require 'onlinepayments/sdk/domain/three_d_secure'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class OnlinePaymentsGateway < Gateway
      self.display_name = 'ANZ Worldline'
      self.homepage_url = 'https://docs.anzworldline-solutions.com.au/en/getting-started/'
      self.supported_countries = %w[US CA GB AU NL DE FR ES IT]
      self.supported_cardtypes = %i[visa master american_express discover jcb]
      self.default_currency = 'AUD'
      self.money_format = :cents

      def initialize(options = {})
        requires!(options, :partner, :login, :password)
        @merchant_id = options[:partner]
        @api_key_id = options[:login]
        @secret_api_key = options[:password]
        @integrator = 'github.com/RGNets/active_merchant'
        @api_endpoint = options[:test] ? 'https://payment.preprod.anzworldline-solutions.com.au' : 'https://payment.anzworldline-solutions.com.au'
        super
        @client = build_client
      end

      def purchase(money, payment, options = {})
        request = build_create_payment_request(money, payment, options, authorization_mode: 'SALE')
        begin
          response = @client.merchant(@merchant_id).payments.create_payment(request)
          success = response&.payment&.status == 'CAPTURED'
          Response.new(
            success,
            response_message(response),
            response.to_h,
            authorization: response&.payment&.id,
            test: test?,
            error_code: success ? nil : response_error_code(response)
          )
        rescue => e
          Response.new(
            false,
            e.message,
            {},
            test: test?,
            error_code: 'sdk_error'
          )
        end
      end

      def authorize(money, payment, options = {})
        request = build_create_payment_request(money, payment, options, authorization_mode: 'PRE_AUTHORIZATION')
        begin
          response = @client.merchant(@merchant_id).payments.create_payment(request)
          success = response&.payment&.status == 'PENDING_APPROVAL' || response&.payment&.status == 'AUTHORIZED'
          Response.new(
            success,
            response_message(response),
            response.to_h,
            authorization: response&.payment&.id,
            test: test?,
            error_code: success ? nil : response_error_code(response)
          )
        rescue => e
          Response.new(
            false,
            e.message,
            {},
            test: test?,
            error_code: 'sdk_error'
          )
        end
      end

      def capture(money, authorization, options = {})
        require 'onlinepayments/sdk/domain/capture_payment_request'
        request = OnlinePayments::SDK::Domain::CapturePaymentRequest.new
        request.amount = money
        begin
          response = @client.merchant(@merchant_id).payments.capture_payment(authorization, request)
          success = response&.payment&.status == 'CAPTURE_REQUESTED' || response&.payment&.status == 'COMPLETED'
          Response.new(
            success,
            response_message(response),
            response.to_h,
            authorization: authorization,
            test: test?,
            error_code: success ? nil : response_error_code(response)
          )
        rescue => e
          Response.new(
            false,
            e.message,
            {},
            test: test?,
            error_code: 'sdk_error'
          )
        end
      end

      def refund(money, authorization, options = {})
        require 'onlinepayments/sdk/domain/refund_request'
        request = OnlinePayments::SDK::Domain::RefundRequest.new
        amount_of_money = OnlinePayments::SDK::Domain::AmountOfMoney.new
        amount_of_money.amount = money
        amount_of_money.currency_code = (options[:currency] || self.default_currency).to_s.upcase
        request.amount_of_money = amount_of_money
        begin
          response = @client.merchant(@merchant_id).payments.refund_payment(authorization, request)
          success = response&.status == 'REFUND_REQUESTED' || response&.status == 'COMPLETED'
          Response.new(
            success,
            response_message(response),
            response.to_h,
            authorization: authorization,
            test: test?,
            error_code: success ? nil : response_error_code(response)
          )
        rescue => e
          Response.new(
            false,
            e.message,
            {},
            test: test?,
            error_code: 'sdk_error'
          )
        end
      end

      def void(authorization, options = {})
        require 'onlinepayments/sdk/domain/cancel_payment_request'
        request = OnlinePayments::SDK::Domain::CancelPaymentRequest.new if defined?(OnlinePayments::SDK::Domain::CancelPaymentRequest)
        begin
          response = @client.merchant(@merchant_id).payments.cancel_payment(authorization, request)
          success = response&.payment&.status == 'CANCELLED'
          Response.new(
            success,
            response_message(response),
            response.to_h,
            authorization: authorization,
            test: test?,
            error_code: success ? nil : response_error_code(response)
          )
        rescue => e
          Response.new(
            false,
            e.message,
            {},
            test: test?,
            error_code: 'sdk_error'
          )
        end
      end

      def verify(payment, options = {})
        # $1 or $0 authorization, then void
        auth = authorize(100, payment, options)
        if auth.success?
          void(auth.authorization, options)
        else
          auth
        end
      end

      private

      def build_client
        config = OnlinePayments::SDK::CommunicatorConfiguration.new(
          api_endpoint: @api_endpoint,
          api_key_id: @api_key_id,
          secret_api_key: @secret_api_key,
          integrator: @integrator,
          authorization_type: 'v1HMAC'
        )
        OnlinePayments::SDK::Factory.create_client_from_configuration(config)
      end

      def build_create_payment_request(money, payment, options, authorization_mode: nil)
        req = OnlinePayments::SDK::Domain::CreatePaymentRequest.new
        card_input = OnlinePayments::SDK::Domain::CardPaymentMethodSpecificInput.new
        card = OnlinePayments::SDK::Domain::Card.new
        card.card_number = payment.number
        card.cardholder_name = payment.name
        card.cvv = payment.verification_value
        card.expiry_date = format_expiry(payment.month, payment.year)
        card_input.card = card
        card_input.payment_product_id = card_brand_id(payment.brand)
        card_input.authorization_mode = authorization_mode if authorization_mode
        
        # Disable 3D Secure authentication
        three_d_secure = OnlinePayments::SDK::Domain::ThreeDSecure.new
        three_d_secure.skip_authentication = true
        card_input.three_d_secure = three_d_secure
        
        req.card_payment_method_specific_input = card_input

        order = OnlinePayments::SDK::Domain::Order.new
        amount_of_money = OnlinePayments::SDK::Domain::AmountOfMoney.new
        amount_of_money.amount = money
        amount_of_money.currency_code = (options[:currency] || self.default_currency).to_s.upcase
        order.amount_of_money = amount_of_money

        # Customer
        customer = OnlinePayments::SDK::Domain::Customer.new
        personal_info = OnlinePayments::SDK::Domain::PersonalInformation.new
        name = OnlinePayments::SDK::Domain::PersonalName.new
        name.first_name = payment.first_name if payment.respond_to?(:first_name)
        name.surname = payment.last_name if payment.respond_to?(:last_name)
        personal_info.name = name
        customer.personal_information = personal_info
        customer.merchant_customer_id = options[:customer] if options[:customer]
        contact = OnlinePayments::SDK::Domain::ContactDetails.new
        contact.email_address = options[:email] if options[:email]
        contact.phone_number = options[:billing_address][:phone] if options[:billing_address]&.key?(:phone)
        customer.contact_details = contact
        # Billing address
        if options[:billing_address]
          billing = OnlinePayments::SDK::Domain::Address.new
          billing.street = options[:billing_address][:address1]
          billing.additional_info = options[:billing_address][:address2]
          billing.zip = options[:billing_address][:zip]
          billing.city = options[:billing_address][:city]
          billing.state = options[:billing_address][:state]
          billing.country_code = options[:billing_address][:country]
          customer.billing_address = billing
        end
        order.customer = customer

        # References
        if options[:order_id] || options[:description]
          refs = OnlinePayments::SDK::Domain::OrderReferences.new
          refs.merchant_reference = options[:order_id] if options[:order_id]
          refs.descriptor = options[:description] if options[:description]
          order.references = refs
        end

        req.order = order
        req
      end

      def card_brand_id(brand)
        # Map ActiveMerchant card brand to OnlinePayments product ID (example mapping)
        {
          'visa' => 1,
          'master' => 3,
          'mastercard' => 3,
          'american_express' => 2,
          'discover' => 128,
          'jcb' => 125
        }[brand.to_s.downcase] || 1
      end

      def format_expiry(month, year)
        "%02d%02d" % [month, year.to_s[-2, 2].to_i]
      end

      def response_message(response)
        if response.respond_to?(:payment) && response.payment.respond_to?(:status)
          "Status: #{response.payment.status}"
        elsif response.respond_to?(:status)
          "Status: #{response.status}"
        else
          'Unknown response'
        end
      end

      def response_error_code(response)
        if response.respond_to?(:errors) && response.errors&.first&.respond_to?(:code)
          response.errors.first.code
        elsif response.respond_to?(:status_output) && response.status_output&.respond_to?(:status_code)
          response.status_output.status_code
        else
          'gateway_error'
        end
      end
    end
  end
end 