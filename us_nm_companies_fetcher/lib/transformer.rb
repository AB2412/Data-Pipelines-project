# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module UsNmCompaniesFetcher
  module Transformer
    extend OpencBot::Helpers::PseudoMachineTransformer

    module_function

    def encapsulate_as_per_schema(payload)
      TransformerHelper.new(input: payload).encapsulate_as_per_schema
    end

    def run
      counter = 0
      start_time = Time.now.utc
      input_data do |json_data|
        entity_datum = encapsulate_as_per_schema(json_data)
        unless entity_datum.blank?
          validation_errors = validate_datum(entity_datum)
          raise "\n#{JSON.pretty_generate([entity_datum, validation_errors])}" unless validation_errors.blank?
          save_entity(entity_datum)
          persist(entity_datum)
          counter += 1
        end
      end

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
        datum = {
          'jurisdiction_code' => 'us_nm',
          'all_attributes' => {},
          'registered_address' => {},
          'alternative_names' => {},
          'filings' => [],
          'officers' => [],
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when 'RECORD_NUM'
            datum['company_number'] = object
          when 'TITLE'
            datum['name'] = object.first
            if object[1].present?
              datum['alternative_names'].push({'company_name' => object[1], 'type' => 'alias'})
            end
          when 'RegistrationDate'
            datum['incorporation_date'] = object
          when 'BusinessStatusId'
            datum['current_status'] = object
          when 'BusinessRecordTypeId'
            datum['company_type'] = object
          when 'Agent'
            officer = {'name' => object, 'position' => 'agent'}
            datum['officers'] << officer
          when 'RetrievedAt'
            datum['retrieved_at'] = object
          end
        end

        if (!datum['company_type'].include? 'Domestic') && input['FormationLocale'] != 'New Mexico'
          datum['branch'] = 'F'
          datum['all_attributes']['jurisdiction_of_origin'] = input['FormationLocale']
        end
        return if datum.blank? || datum['name'].blank? || datum['company_number'].blank?

        datum['officers']&.delete_if { |officer| officer['name'].blank? || officer['name'][/#{INVALID_OFFICER}/] }
        datum['all_attributes'].snap
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        datum.snap
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
