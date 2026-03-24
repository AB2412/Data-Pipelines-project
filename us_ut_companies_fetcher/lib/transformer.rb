# frozen_string_literal: true
require 'openc_bot/helpers/pseudo_machine_transformer'

module UsUtCompaniesFetcher
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

      def address(entry, address_keys)
        street_address = address_keys[0].map { |k| entry[k]}
        street_address = street_address.snap.uniq.join(', ')
        region = address_keys[2].map { |k| entry[k]}
        region = region.snap.uniq.join(', ')
        postal_code = address_keys[3].map { |k| entry[k]}
        postal_code = postal_code.snap.uniq.join('-')
        address_data = {
          'street_address' => street_address,
          'locality' => entry[address_keys[1]].to_s,
          'region' => region,
          'postal_code' => postal_code,
          'country' => entry[address_keys[4]]
        }
        clean_address(address_data.snap)
      end

      def get_dissolution_date(value, current_status, date_status_changed)
        if current_status == 'Active'
          ""
        elsif date_status_changed.blank?
          normalise_date(value)
        else
          normalise_date(date_status_changed)
        end
      end

      def encapsulate_as_per_schema
        datum = {
          'jurisdiction_code': 'us_ut',
          'all_attributes' => {},
          'registered_address' => {},
          'industry_codes' => [],
          'officers' => [],
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, objects|
          case legend
          when 'busentity'
            object = objects.last.snap
            object.each do |key, value|
              case key
              when 'Entity Number'
                datum['company_number'] = value
              when 'Business Name'
                datum['name'] = value
              when 'Entity Type'
                datum['company_type'] = value
                return nil if ["Assumed Name (DBA)"].include? (datum['company_type'])
              when 'Address'
                datum['registered_address'] = address(object, REGISTERED_ADDRESS_SCHEMA)
              when 'Registration Date'
                datum['incorporation_date'] = normalise_date(value)
              when 'License Status'
                datum['current_status'] = value
              when 'Expiration Date'
                datum['dissolution_date'] = get_dissolution_date(value, object["License Status"], object['Date Status Changed'])
              when 'Home State'
                datum['all_attributes']['jurisdiction_of_origin'] = value
              when 'Last Renewal Date'
                datum['all_attributes']['last_renewal_date'] = normalise_date(value)
              when 'NAICS Code'
                scheme_code = get_scheme_code(value)
                if scheme_code.nil?
                  datum['all_attributes']['invalid_naics_code'] = {'code' => value}
                else
                  datum['industry_codes'] << { 'code' => value , 'code_scheme_id' => scheme_code}
                end
              end
            end
          when 'businfo'
            objects.each do |object|
              object.each do |key, value|
                case key
                when "Female Owned"
                  datum['all_attributes']['female_owned'] = value
                when "Minority Owned"
                  datum['all_attributes']['minority_owned'] = value
                end
              end
            end
          when 'principal', 'pricipals'
            objects.each do |object|
              officer = {'other_attributes' => {'address' => address(object, REGISTERED_ADDRESS_SCHEMA)}.snap}
              officer['name'] = object['Full name']

              if object['Member Position'] == "Registered Agent"
                officer['position'] = 'agent'
              else
                officer['position'] = object['Member Position']
              end
              datum['officers'] << officer.snap
            end
          when 'RetrievedAt'
            datum['retrieved_at'] = objects
          end
        end

        if datum['company_type'].to_s[/Foreign/i]
          datum['branch'] = 'F'
        end
        return if datum.blank? || datum['name'].blank? || datum['company_number'].blank?
        datum['officers']&.delete_if { |officer| officer['name'].blank? || officer['name'][/#{INVALID_OFFICER}/] || INVALID_OFFICERS.any? {|invalid| officer['name'].include?(invalid) } || INVALID_OFFICERS.any? {|invalid| officer['name'].downcase.include?(invalid.downcase) }}
        datum['all_attributes'].snap
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        datum.snap
        datum['dissolution_date'] = '' if datum['dissolution_date'].blank?
        datum['branch'] = nil if datum['branch'].blank?
        datum
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
