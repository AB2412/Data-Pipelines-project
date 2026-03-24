# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module UsNh2CompaniesFetcher
  module Transformer
    extend OpencBot::Helpers::PseudoMachineTransformer

    module_function

    def encapsulate_as_per_schema(payload)
      TransformerHelper.new(input: payload).encapsulate_as_per_schema
    end

    class TransformerHelper
      include OpencBot::Helpers::RegisterMethods
      def initialize(input)
        input.each do |key, value|
          self.class.__send__(:attr_accessor, key)
          __send__("#{key}=", value)
        end
      end

      def defaults(datum)
        datum[:branch] = nil if datum[:branch].blank?
        datum[:officers] = [] if datum[:officers].blank?
        datum[:dissolution_date] = '' if datum[:dissolution_date].blank?
        datum
      end

      def get_parse_date(date_value)
        Date.strptime(date_value, "%Y-%m-%d") rescue nil
      end

      def get_locality(county_value, city_value)
        return city_value if city_value&.casecmp?(county_value)

        [city_value, county_value].compact.join(((!county_value.blank?) && (!city_value.blank?)) ? ", " : " ")
      end

      def get_street_address(address_1, address_2)
        [address_1, address_2].compact.join(((!address_1.blank?) && (!address_2.blank?)) ? ", " : " ")
      end

      def process_registered_agent(datum, object)
        object.each do |obj|
          officer = {other_attributes: {address:{}, mailing_address: {}}}
          obj.each { |key, value| process_registered_agent_fields(officer, key, value, obj) }
          officer[:other_attributes][:address] = clean_address(officer[:other_attributes][:address].snap)
          officer[:other_attributes][:mailing_address] = clean_address(officer[:other_attributes][:mailing_address].snap)
          officer[:other_attributes] = officer[:other_attributes].snap
          datum[:officers] << officer.snap
        end
      end

      def process_registered_agent_fields(officer, key, value, obj)
        case key
        when "RegisteredAgentName"
          officer[:name] = value.squish
          officer[:position] = "agent"
        when "RegisteredAgentType"
          officer[:other_attributes][:type] = (value == "Individual") ? "Person" : "Company"
        when "PrincipalOfficeStreetAddress"
          officer[:other_attributes][:address][:street_address] = get_street_address(value, obj["PrincipalOfficeStreetAddress2"]).squish
        when "PrincipalOfficeCity"
          officer[:other_attributes][:address][:locality] = get_locality(obj["PrincipalOfficeCounty"], value).squish
        when "PrincipalOfficeState"
          officer[:other_attributes][:address][:region] = value
        when "PrincipalOfficeZip"
          officer[:other_attributes][:address][:postal_code] = value
        when "PrincipalOfficeCountry"
          officer[:other_attributes][:address][:country] = value
        when "MailingStreetAddress"
          officer[:other_attributes][:mailing_address][:street_address] = get_street_address(value, obj["MailingStreetAddress2"]).squish
        when "MailingCity"
          officer[:other_attributes][:mailing_address][:locality] = get_locality(obj["MailingCounty"], value).squish
        when "MailingState"
          officer[:other_attributes][:mailing_address][:region] = value
        when "MailingZip"
          officer[:other_attributes][:mailing_address][:postal_code] = value
        when "MailingCountry"
          officer[:other_attributes][:mailing_address][:country] = value
        end
      end

      def process_filling(datum, object)
        object.each do |obj|
          filing = {other_attributes: {}}
          obj.each { |key, value| process_filing_fields(filing, key, value) }
          filing[:other_attributes].snap
          datum[:filings] << filing.snap if valid_filing?(filing)
        end
      end

      def process_filing_fields(filing, key, value)
        case key
        when "FilingDateTime"
          filing[:date] = get_parse_date(value)
        when "EffectiveDate"
          filing[:other_attributes][:effective_date] = get_parse_date(value)
        when "FilingType"
          filing[:title] = FILING_TYPE_TO_FILING_TITLE[value] || value
          filing[:filing_type_name] = value
        when "FilingNumber"
          filing[:uid] = value.to_s.rjust(10, '0') if value
        end
      end

      def handle_business_status(datum, value)
        if REJECTED_STATUS.include?(value)
          warn "STATUS REJECTED"
          return nil
        else
          value
        end
      end

      def handle_business_type(datum, value)
        if REJECTED_COMPANY_TYPE.include?(value)
          warn "COMPANY TYPE REJECTED"
          return nil
        else
          value
        end
      end

      def handle_duration(datum, value)
        case value
        when "9999-09-09"
          "Not Stated"
        when "9999-01-01"
          "Perpetual"
        else
          get_parse_date(value)
        end
      end

      def handle_citizenship_or_state(datum, value)
        datum[:all_attributes]["State of Business"] = value
        if datum[:company_type]&.downcase&.include?("foreign")
          if value.downcase == 'new hampshire'
            datum[:all_attributes][:jurisdiction_of_origin] = nil
            datum[:branch] = nil
          else
            datum[:all_attributes][:jurisdiction_of_origin] = value
            datum[:branch] = 'F'
          end
        end
      end

      def handle_business_details(datum, key, value)
        case key
        when "BusinessID"
          datum[:company_number] = value
          warn "COMPANY_NUMBER: #{datum[:company_number]}"
        when "BusinessName"
          datum[:name] = value
        when "HomeStateName"
          datum[:all_attributes][:home_legal_name] = value.squish
        when "BusinessStatus"
          datum[:current_status] = handle_business_status(datum, value)
        when "BusinessType"
          datum[:company_type] = handle_business_type(datum, value)
        when "CreationDate"
          datum[:incorporation_date] = get_parse_date(value)
        when "DateInJurisdiction"
          datum[:all_attributes][:formation_date] = get_parse_date(value)
        when "Duration"
          datum[:all_attributes]["Expiration Date"] = handle_duration(datum, value)
        when "ManagementStyle"
          datum[:all_attributes]["Management Style"] = value
        when "FiscalYearDate"
          datum[:all_attributes]["Fiscal Year End Date"] = value
        when "CitizenshipOrStateOfIncorporation"
          handle_citizenship_or_state(datum, value)
        when "LastBenefitReportYear"
          datum[:all_attributes]["Last Benefit Report Year"] = value
        when "NextBenefitReportYear"
          datum[:all_attributes]["Next Benefit Report Year"] = value
        when "LastAnnualReportYear"
          datum[:all_attributes]["Last Annual Report Filed"] = value
        when "NextAnnualReportYear"
          datum[:all_attributes]["Next Report Year"] = value
        when "BusinessEmail"
          datum[:all_attributes][:email] = value
        when "NotificationEmail"
          datum[:all_attributes][:notification_email] = value
        when "PhoneNumber"
          datum[:telephone_number] = reformat_phone_number(value)
        end
      end

      def reformat_phone_number(phone_number)
        digits = phone_number.gsub(/\D/, '') # Remove non-digit characters
        if digits.length == 10
          digits.insert(3, '-').insert(7, '-')
        else
          phone_number
        end
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: 'us_nh',
          all_attributes: { total_shares: [] },
          registered_address: {},
          filings: [],
          officers: [],
          previous_names: [],
          mailing_address: {},
          alternative_names: []

        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when 'RegisteredAgent'
            process_registered_agent(datum, object)
          when 'PrincipalPurpose'
          when 'Filing'
            process_filling(datum, object)
          when 'PreviousBusinessNames'
            object.each do |obj|
              case obj["PreviousNameType"]
              when nil, '', 'Prev Legal', 'Prev Home State'
                datum[:previous_names] << {company_name: obj['PreviousName']}
              when 'Legal', 'Home State'
                datum[:alternative_names] << {company_name: obj['PreviousName'], type: 'legal'}
              when 'Reserved'
              end
            end
          when 'BusinessDetails'
            object.each do |obj|
              obj.each do |key, value|
                handle_business_details(datum, key, value)
              end
              return nil if (datum[:current_status].blank?) || (datum[:company_type].blank?)
            end
          when 'Stock'
            object.each do |obj|
              total_share = {}
              obj.each do |key, value|
                case key
                when 'ShareClass'
                  total_share[:share_class] = value
                when 'NumberOfShares'
                  total_share[:number_of_shares] = value.to_i
                when 'ParValue'
                  #No mapping
                when 'Note'
                  #No mapping
                end
              end
              datum[:all_attributes][:total_shares] << total_share.snap
            end
          when 'Principals'
            object.each do |obj|
              officer = {other_attributes: {address:{}}}
              obj.each do |key, value|
                case key
                when "PrincipalName"
                  officer[:name] = value
                when "PrincipalTitle"
                  officer[:position] = value
                when "PrincipalStreetAddress"
                  officer[:other_attributes][:address][:street_address] = get_street_address(value, obj["PrincipalStreetAddress2"]).squish
                when "PrincipalCity"
                  officer[:other_attributes][:address][:locality] = get_locality(obj["PrincipalCounty"], value).squish
                when "PrincipalState"
                  officer[:other_attributes][:address][:region] = value
                when "PrincipalZip"
                  officer[:other_attributes][:address][:postal_code] = value
                when "PrincipalCountry"
                  officer[:other_attributes][:address][:country] = value
                end
              end
              officer[:other_attributes][:address] = clean_address(officer[:other_attributes][:address].snap)
              officer[:other_attributes] = officer[:other_attributes].snap
              datum[:officers] << officer.snap
            end
          when 'BusinessAddress'
            object.each do |obj|
              obj.each do |key, value|
                case key
                when 'PrincipalOfficeStreetAddress'
                  datum[:registered_address][:street_address] = get_street_address(value,obj["PrincipalOfficeStreetAddress2"]).squish
                when 'PrincipalOfficeCity'
                  datum[:registered_address][:locality] = get_locality(obj["PrincipalOfficeCounty"], value).squish
                when "PrincipalOfficeState"
                  datum[:registered_address][:region] = value
                when "PrincipalOfficeZip"
                  datum[:registered_address][:postal_code] = value
                when "PrincipalOfficeCountry"
                  datum[:registered_address][:country] = value
                when "MailingStreetAddress"
                  datum[:mailing_address][:street_address] = get_street_address(value,obj["MailingStreetAddress2"]).squish
                when "MailingCity"
                  datum[:mailing_address][:locality] = get_locality(obj["MailingCounty"], value).squish
                when "MailingState"
                  datum[:mailing_address][:region] = value
                when "MailingZip"
                  datum[:mailing_address][:postal_code] = value
                when "MailingCountry"
                  datum[:mailing_address][:country] = value
                end
              end
            end
          when 'RetrievedAt'
            datum[:retrieved_at] = object
          else
            raise "Unhandled legend: #{legend}"
          end
        end
        return nil if datum.blank?

        datum[:officers]&.delete_if { |officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/] }

        datum[:all_attributes] = datum[:all_attributes].snap
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        return nil if datum[:name].blank?
        return nil if datum[:company_number].blank?

        datum[:registered_address] = clean_address(datum[:registered_address].snap)
        datum[:mailing_address] = clean_address(datum[:mailing_address].snap)
        datum.snap

        if ['Good Standing', 'Active'].include?(datum[:current_status])
          datum[:dissolution_date] = ''
        else
          $stderr.puts "Dissolution Date Added"
          dissolution_date = (datum[:filings] && datum[:filings].select{|item| FILING_TYPES.include?(item[:filing_type_name])}.sort_by{|item| item[:other_attributes][:effective_date]}.last[:other_attributes][:effective_date] rescue nil)
          datum[:dissolution_date] = dissolution_date

          if datum[:dissolution_date].blank?
            dissolution_date = (datum[:filings] && datum[:filings].select{|item| ['Consolidation'].include?(item[:filing_type_name])}.sort_by{|item| item[:other_attributes][:effective_date] }.last[:other_attributes][:effective_date] rescue nil)
            unless dissolution_date.blank?
              datum[:dissolution_date] = dissolution_date
            end
          end
        end
        datum[:all_attributes][:total_shares] = datum[:all_attributes][:total_shares].uniq if datum[:all_attributes][:total_shares]
        datum = squish_values(datum)
        defaults(datum)
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
