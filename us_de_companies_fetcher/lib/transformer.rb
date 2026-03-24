require 'openc_bot/helpers/pseudo_machine_transformer'

module UsDeCompaniesFetcher
  module Transformer
    extend UsDeCompaniesFetcher
    extend OpencBot::Helpers::PseudoMachineTransformer
    extend self

    def encapsulate_as_per_schema(payload)
      TransformerHelper.new(input: payload).encapsulate_as_per_schema
    end

    class TransformerHelper
      def initialize(input)
        input.each do |key, value|
          self.class.__send__(:attr_accessor, key)
          __send__("#{key}=", value)
        end
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: 'us_de',
          all_attributes: {},
          officers: [],
        }

        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          officer_hash = {"position": "agent"}
          registered_address_hash = {}
          com_state = nil
          if legend != 'RetrievedAt'
            object.first.strip.snap.each do |key,value|
              case key
              when 'officer_uid'
                officer_hash[:uid] = value
              when 'officer_name'
                officer_hash[:name] = value
              when 'officer_address'
                officer_hash[:other_attributes] = {address: {street_address: value}.strip.snap}
              when 'Company_NAME'
                datum[:name] = value
              when 'company_type'
                datum[:company_type] = value
              when 'Company_FILE_NR'
                datum[:company_number] = value
              when 'Company_DATE_INC'
                datum[:incorporation_date] = DateTime.strptime(value, "%m/%d/%Y").strftime("%Y-%m-%d")
              when 'Company_COUNTY'
                registered_address_hash[:locality] = value
              when 'Company_STATE'
                registered_address_hash[:region] = value
                com_state = value
              when 'Company_CORP_TYPE'
                datum[:all_attributes][:CORP_TYPE] = value
              when 'Company_TAX_TYPE'
                datum[:all_attributes][:TAX_TYPE] = value
              end
            end
            datum[:branch] = 'F' if datum[:company_type].to_s[/foreign/i]

            if datum[:branch] && com_state
              datum[:all_attributes][:jurisdiction_of_origin] = com_state
            end

            datum[:registered_address] = "#{registered_address_hash[:locality]}, #{registered_address_hash[:region]}" 
            datum[:officers] << officer_hash
          elsif legend == 'RetrievedAt'
            datum[:retrieved_at] = object
          end
        end
        return if datum[:company_number].nil?
        datum[:officers] && datum[:officers].delete_if{|item| item[:name][/#{INVALID_OFFICER}/]}
        datum.snap
      end
    end
  end
end
