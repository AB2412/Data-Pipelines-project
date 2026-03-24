# encoding: iso-8859-1
require 'csv'
require 'openc_bot/helpers/dates'
require_relative 'common'
require 'tzinfo'

module AuCompaniesFetcher
  class APIParser
    include OpencBot::Helpers::Dates
    include OpencBot::Helpers::RegisterMethods
    attr_accessor :entry

    TERRITORY_CODE_MAPPING = {
      'ACT' => 'Australian Capital Territory',
      'NSW' => 'New South Wales',
      'NT' => 'Northern Territory',
      'QLD' => 'Queensland',
      'SA' => 'South Australia',
      'TAS' => 'Tasmania',
      'VIC' => 'Victoria',
      'WA' => 'Western Australia',
    }.freeze

    ADDRESS_CODES = [%w(PA GD), %w(RG RP RO GE GC), %w(GL)].freeze

    def initialize(input)
      @entry = Hash.from_xml(input)
    rescue REXML::ParseException => ex
      IO.write('data/invalid_details_at_apiparser.xml', input)
      raise ex
    end

    def addresses_as_per_schema(addresses)
      addresses = [addresses] if addresses.is_a? Hash
      addresses.map do |item|
        case item['type']
        when 'RG', 'RP', 'RO', 'GE', 'GC'
          { registered_address: address_as_per_schema(item.except('type')) }
        when 'PA', 'GD'
          { headquarters_address: address_as_per_schema(item.except('type')) }
        when 'GL'
          { mailing_address: address_as_per_schema(item.except('type')) }
        else
          raise 'Unhandled address type: ' + item.to_json
        end
      end.reject(&:blank?).inject(&:update)
    end

    def address_as_per_schema(item)
      address = item.map do |key, value|
        case key
        when 'addressLine'
          { street_address: value } 
        when 'iso3166CountryCode'
          { country_code: value }
        when 'locality'
          { locality: value }
        when 'state'
          { region: (TERRITORY_CODE_MAPPING[value] || value ) }
        when 'postCode'
          { postal_code: value }
        when 'country'
          { country: value }
        else
          raise 'Unhandled address pair: ' + [key, value].to_json
        end
      end.inject(&:update)
      cleaned_address(address.compact)
    end

    def filings(document)
      document && document.map do |item|
        filing_as_per_schema(item)
      end
    end

    def filing_as_per_schema(item)
      filing = { other_attributes: {} }
      item.delete_if{|_k, v| v.blank?}.each do |key, value|
        case key
        when 'documentNumber'
          filing[:uid] = value
        when 'dateReceived'
          filing[:date] = normalise_us_date(value)
        when 'description'
          filing[:title] = value
          filing[:filing_type_name] = value
        when 'formCode'
          filing[:filing_type_code] = value
        when 'numberOfPages'
          filing[:other_attributes][key] = value
        when 'additionalDescription'
          value = [value] if value.is_a?(Hash)
          filing[:other_attributes]['subForm'] = []
          value.each{|item|
            filing[:other_attributes]['subForm'] << {'subformCode' => item['subformCode'], 'subformDescription' => item['subformDescription']}
          }
        end
      end
      filing[:other_attributes].compact
      filing.compact if valid_filing?(filing)
    end

    def encapsulate_as_per_schema
      return nil if entry.blank?
      datum = {
        retrieved_at: ( entry['Envelope']['Body']['reply']['businessDocumentHeader']['messageTimestamps']['messageTimestamp']['timestamp'] || Time.now.utc.iso8601 ),
        jurisdiction_code: 'au',
        all_attributes: {},
        officers: [],
        previous_names: [],
        filings: [],
        alternative_names: []
      }
      datum[:company_type] = Array.new(2)
      entry['Envelope']['Body']['reply']['businessDocumentHeader'].compact.each do |key, value|
        case key
        when 'messageType', 'messageVersion'
          datum[:all_attributes][key] = value
        when 'messageTimestamps'
          datum[:retrieved_at] = ActiveSupport::TimeZone['Australia/Sydney'].parse((value['messageTimestamp']['timestamp'])).utc.iso8601
        end
      end
      entry['Envelope']['Body']['reply']['businessDocumentBody']['nniEntity'].compact.each do |key, value|
        case key
        when 'identifier'
          datum[:all_attributes]['numberHeading'] = value['numberHeading']
          datum[:company_number] = format('%09i', value['number'])
        when 'name'
          datum[:name] = value['name']
          datum[:all_attributes]['distinguishedWord'] = value['distinguishedWord']
        when 'type'
          if ['RSVD', 'RSVN', 'BUSN'].include?(value['code'])
            $stderr.puts "Ignoring Name Reservation's"
            return nil
          end
          if ['NONC', 'NRET'].include?(value['code'])
            $stderr.puts "Ignoring body/entity not registered under corporations act 2001"
            return nil
          end
          if ['OBJN'].include?(value['code'])
            $stderr.puts "Ignoring entries which have objection to registration of name"
            return nil
          end
          datum[:branch] = 'F' if value['code'] == 'FNOS'
          datum[:company_type][0] = value['description']
          datum[:all_attributes][:types_code] = value['code']
        when 'class'
          datum[:all_attributes][:types_class_code] = value['code']
          datum[:company_type][1] = case value['code']
                                    when 'NONE'
                                      nil
                                    when 'UNKN'
                                      'Liability Unknown'
                                    else
                                      value['description']
                                    end
        when 'subClass'
          datum[:all_attributes][:types_subclass_code] = value['code']
          datum[:all_attributes][:types_subclass_descr] = case value['code']
                                    when 'NONE', 'UNKN'
                                      nil
                                    else
                                      value['description']
                                    end
        when 'previousStateTerritory'
          unless value.blank?
            datum[:all_attributes][key] = value
          end
        when 'acncFlag'
          datum[:all_attributes][:non_profit] = value
        when 'status'
          ['APPD', 'RSVD'].include?(value['code'])
          datum[:all_attributes][:status_code] = value['code']
          datum[:current_status] = value['description']
          datum[:all_attributes][:is_registered] = value['isRegistered']
        when 'dateRegistered'
          tmp = Date.parse(normalise_us_date(value))
          datum[:incorporation_date] = if tmp <= Date.parse('1700-01-01')
                                         nil
                                       else
                                         tmp.iso8601
                                       end
        when 'dateDeregistered'
          tmp = Date.parse(normalise_us_date(value))
          datum[:dissolution_date] = if tmp <= Date.parse('1700-01-01')
                                       nil
                                     else
                                       tmp.iso8601
                                     end
        when 'dateReview', 'dateRenewal'
          datum[:all_attributes][key] = normalise_us_date(value)
        when 'incorporationState'
          datum[:all_attributes][key] = value
        when 'jurisdiction'
          datum[:all_attributes][:regulator] = value
        when 'placeOfIncorporation'
          datum[:all_attributes][:jurisdiction_of_origin] = value
        when 'address'
          value = [value] if value.is_a?(Hash)
          tmp = ADDRESS_CODES.map do |codes|
            addresses = codes.map do |code|
              value.select { |item| item['type'] == code }.first
            end.reject(&:blank?)
            addresses_as_per_schema(addresses)
          end.reject(&:blank?)
          unless tmp.blank?
            datum.update(addresses_as_per_schema(value))
          end
        when 'recentDocument'
          datum[:filings] = filings(value)
        when 'abrEntity'
          datum[:identifiers] = [{ uid: value['abn'], identifier_system_code: 'au_bn' }]
          datum[:alternative_names] = [{company_name: value['entityName'], type: 'legal'}] if datum[:name] != value['entityName']
        when 'formerName'
          value = [value] if value.is_a? Hash
          value.each do |item|
            datum[:previous_names] << {company_name: item['organisationName'], start_date: normalise_us_date(item['startDate']), con_date: normalise_us_date(item['endDate'])}.compact
          end
        when 'bnReferenceNumber'
          # ignored entries
        else
          raise 'Unhandled key-value pair: ' + [key, value].to_json
        end
      end
      datum[:company_type] = datum[:company_type][0..1].reject(&:blank?).join(', ')
      datum[:filings].compact
      datum[:all_attributes].compact
      defaults(datum.compact)
    end

    def defaults(datum)
      if datum[:branch].blank?
        datum[:branch] = nil
      end
      if datum[:incorporation_date].blank?
        datum[:incorporation_date] = ''
      end
      if datum[:dissolution_date].blank?
        datum[:dissolution_date] = ''
      end
      datum
    end
  end
end
