# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module CaOnCompaniesFetcher
  module Transformer
    extend OpencBot::Helpers::PseudoMachineTransformer

    module_function

    def encapsulate_as_per_schema(payload)
      TransformerHelper.new(input: payload).encapsulate_as_per_schema
    end

    def run
      counter = 0
      start_time = Time.now.utc
      transformer_data = {}
      input_data do |json_data|
        entity_datum = encapsulate_as_per_schema(json_data)
        unless entity_datum.blank?
          validation_errors = validate_datum(entity_datum)
          raise "\n#{JSON.pretty_generate([entity_datum, validation_errors])}" unless validation_errors.blank?
          transformer_data[entity_datum["company_number"]] = entity_datum
          counter += 1
        end
      end

      transformer_data.values.each do |datum|
        persist(datum)
        save_entity(datum) unless ENV["NO_SAVE_DATA_IN_SQLITE"]
      end
      rename_working_data_folder
      res = { transformed: counter, transformer_start: start_time, transformer_end: Time.now.utc }
      res.merge!({ no_transformed_data: true }) if counter == 0
      res
    end

    class TransformerHelper
      def initialize(input)
        input.each do |key, value|
          self.class.__send__(:attr_accessor, key)
          __send__("#{key}=", value)
        end
      end

      def encapsulate_as_per_schema
        datum = {}
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when 'data'
            datum = object
          when 'RetrievedAt'
            datum['retrieved_at'] = object
          end
        end

        return nil if (datum.blank? || datum['name'].blank? || datum['company_number'].blank?)

        datum['officers']&.delete_if { |officer| officer['name'].blank? || officer['name'][/#{INVALID_OFFICER}/] }
        datum['industry_codes']&.delete_if { |industry_code| industry_code.snap['name'].blank? || industry_code.snap['code'].blank? }
        datum['all_attributes'].snap if datum['all_attributes']

        unless validate_address(datum['headquarters_address'])
          datum['headquarters_address'] = {}
        end

        unless validate_address(datum['registered_address'])
          datum['registered_address'] = {}
        end

        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        datum.snap
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
