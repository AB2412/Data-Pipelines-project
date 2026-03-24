# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module UsMt2CompaniesFetcher
  module Transformer
    extend OpencBot::Helpers::PseudoMachineTransformer

    module_function

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
          jurisdiction_code: 'us_mt',
          all_attributes: {},
          registered_address: {},
          filings: [],
          officers: [],
          mailing_address: {},
        }
        officer = {
          other_attributes: { address: {} }
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when "Entity Name"
            datum[:name] = object
          when "Business Identifier"
            datum[:company_number] = object
          when "Formation Date"
            datum[:incorporation_date] = Date.strptime(object, '%m/%d/%Y') unless object.nil?
          when "Expiration Date"
            datum[:dissolution_date] = Date.strptime(object, '%m/%d/%Y') unless object == "None"
          when "Entity Status"
            datum[:current_status] = object
          when "Entity Type"
            datum[:company_type] = object
            datum[:branch] = (datum[:company_type].include? "Foreign") ? "F" : nil
          when "Entity Subtype"
            datum[:all_attributes][:entity_subtype] = object
          when "Management Type"
            datum[:all_attributes][:management_type] = object
          when "Duration Term"
            datum[:all_attributes][:duration_term] = object
          when "Registered Agent name"
            officer[:name] = object
            officer[:position] = "agent"
          when "Registered Agent Address"
            officer[:other_attributes][:address][:street_address] =  object.split("\;").select{|e| e.include? "Principle"}.first.gsub("Principle:","").squish
          when "Jurisdiction"
            datum[:all_attributes][:jurisdiction_of_origin] = object
          when "Business Mailing Address of Principal Office"
            datum[:mailing_address][:street_address] = object
          when "Purpose"
            datum[:all_attributes][:business_classification_text] = object
          when "Share Information (Class, Series, # Authorized, # Shares, Value)"
          when "Trademark Design Type"
          when "Trademark Class and Description"
          when "Trademark Mode or Manner"
          when 'RetrievedAt'
            datum[:retrieved_at] = object
          else
            raise "Unhandled legend: #{legend}"
          end
        end
        datum[:officers] << officer
        return nil if datum.blank?
        datum[:company_type] = datum[:company_type].sub("-", " ")
        datum[:current_status] = datum[:current_status].sub("-", " ")
        datum[:officers]&.delete_if { |officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/] }
        datum[:all_attributes].snap
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        return nil if datum[:name].blank?
        return nil if datum[:company_number].blank?
        datum.snap
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
