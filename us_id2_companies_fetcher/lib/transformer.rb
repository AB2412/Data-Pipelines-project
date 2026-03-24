# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module UsId2CompaniesFetcher
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
        street_address = address_keys[0].map { |k| entry.delete(k)}
        street_address = street_address.snap.select { |value| !value.strip.match?(/^[-*]+$/) }
        street_address = street_address.uniq.join(', ')
        locality = address_keys[1].map { |k| entry.delete(k)}
        locality = locality.snap.uniq.join(', ')
        address_data = {
          'street_address' => street_address,
          'locality' => locality,
          'region' => entry.delete(address_keys[2]),
          'postal_code' => [entry.delete(address_keys[3])].snap.uniq.join('-'),
          'country' => entry.delete(address_keys[4])
        }
        clean_address(address_data.snap)
      end

      def officer_name(officer, org_name, first_name, middle_name, last_name)
        officer['name'] = if org_name.present?
          org_name
        else
          [first_name, middle_name, last_name].snap.join(' ')
        end
        officer['name'].squeeze!(' ')
        officer['other_attributes']['type'] = if org_name && first_name.blank? && middle_name.blank? && last_name.blank?
          'Company'
        elsif org_name.blank? && (first_name || middle_name || last_name)
          'Person'
        else
          nil
        end
      end

      def encapsulate_as_per_schema
        datum = {
          'jurisdiction_code' => 'us_id',
          'all_attributes' => {},
          'registered_address' => {},
          'alternative_names' => [],
          'previous_names' => [],
          'filings' => [],
          'officers' => [],
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when 'FILING_NAME'
            object.each do |obj|
              name_type = obj['NAME_TYPE']
              case name_type
              when 'Current'
                datum['alternative_names'].push(
                  {
                    'company_name' => obj['NAME'],
                    'type' => 'unknown'
                  }
                )
              when 'Foreign Name'
                datum['all_attributes']['home_legal_name'] = obj['NAME']
              when 'Old Name'
                datum['previous_names'].push(
                  {
                    'company_name' => obj['NAME']
                  }
                )
              end
            end
          when 'FILING'
            object.each do |obj|
              datum['registered_address'] = address(obj, REGISTERED_ADDRESS)
              datum['mailing_address'] = address(obj, MAILING_ADDRESS)
              obj.each do |key, value|
                case key
                when *FILING_DATUM_ATTRIBUTES.keys
                  datum[FILING_DATUM_ATTRIBUTES[key]] = value
                when *FILING_ALL_ATTRIBUTES.keys
                  datum['all_attributes'][FILING_ALL_ATTRIBUTES[key]] = value
                when 'COMMON_SHARES'
                  datum['total_shares'] = {}
                  if value.to_i > 0
                    datum['total_shares']['number'] = value.to_i
                    datum['total_shares']['share_class'] = 'Common'
                  end
                end
              end
            end
          when 'PARTY'
            object.each do |obj|
              officer = { 'other_attributes' => {} }
              officer['other_attributes']['address'] = address(obj, OFFICER_ADDRESS)
              officer_name(officer, obj['ORG_NAME'], obj['FIRST_NAME'], obj['MIDDLE_NAME'], obj['LAST_NAME'])
              positions = []
              obj.each do |key, value|
                case key
                when 'PARTY_TYPE'
                  case value
                  when *['Registered Agent','Commercial Registered Agent']
                    officer['position'] = 'agent'
                    officer['other_attributes']['title'] = value
                  when 'None Specified'
                    officer['position'] = nil
                  else
                    if value.include? '/'
                      positions = value.split('/')
                    else
                      officer['position'] = value
                    end
                  end
                when 'SOURCE_ID'
                  datum['all_attributes']['source_id'] = value.to_i if value
                when 'SOURCE_TYPE'
                  datum['all_attributes']['source_type'] = value
                end
              end
              officer['other_attributes'].snap
              officer.snap
              next if officer['name'].blank? || officer['other_attributes']['type'].blank?
              if positions.blank?
                datum['officers'].push(officer.snap)
              else
                positions.each do |position|
                  tmp = officer.clone
                  tmp['position'] = position
                  datum['officers'].push(tmp)
                end
              end
            end
          when 'RetrievedAt'
            datum['retrieved_at'] = object
          else
            raise "Unhandled legend: #{legend}"
          end
        end

        datum['officers']&.delete_if { |officer| officer['name'].blank? || officer['name'][/#{INVALID_OFFICER}/] }
        datum['officers'].uniq! { |officer| [officer['name'], officer['position']] }
        datum['alternative_names'].uniq! { |name| name['company_name'] }
        datum['name'].strip!
        datum['alternative_names'].delete_if { |name| name['company_name'].strip == datum['name'] }
        datum['alternative_names'].each do |name|
          if name['company_name'].upcase.strip == datum['name']
            puts "Swapping #{name['company_name']} with #{datum['name']}"
            tmp = name['company_name'].strip
            name['company_name'] = datum['name']
            datum['name'] = tmp
          end
        end

        datum['previous_names'].uniq! { |name| name['company_name'] }
        if datum['all_attributes']['State of Origin'].downcase != 'idaho'
          datum['all_attributes']['jurisdiction_of_origin'] = datum['all_attributes']['State of Origin']
          datum['branch'] = 'F'
        end
        if datum['company_type'].downcase.include? 'foreign'
          datum['branch'] = 'F'
        end
        object_date_format(datum, ['incorporation_date', 'dissolution_date'])
        object_date_format(datum['all_attributes'], ['expiration_date', 'home_incorporation_date', 'AR Due Date', 'Delayed Effective Date'])
        datum['all_attributes'].snap

        return nil if datum.blank? || datum['name'].blank? || datum['company_number'].blank? || (EXCLUDE_COMPANY_TYPES.include? datum['company_type'])
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        strip_values(datum)
        datum.snap
        if datum['dissolution_date'].blank?
          datum['dissolution_date'] = ''
        end
        datum
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
