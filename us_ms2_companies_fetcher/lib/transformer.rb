# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module UsMs2CompaniesFetcher
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
          transformer_data[entity_datum[:company_number]] = entity_datum
          counter += 1
        end
      end

      transformer_data.values.each do |datum|
        persist(datum)
        save_entity(datum) unless ENV["NO_SAVE_DATA_IN_SQLITE"]
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

      def get_address(datum, data_values)
        data_values = get_clean_address_hash(data_values)
        address_type = data_values["AddressType"]["_attributes"]["Type"]
        datum_hash = (address_type == "Mailing") ? datum[:mailing_address] : datum[:headquarters_address]
        street_address = [data_values["Address1"], data_values["Address2"]].join(" ").squish
        datum_hash[:street_address] = street_address
        datum_hash[:locality] = data_values["City"]
        datum_hash[:region] = data_values["StateOrProvince"]
        datum_hash[:postal_code] = data_values["PostalCode"]
        datum_hash[:country] = data_values["Country"]
        datum
      end

      def get_clean_address_hash(data_values)
        data_values.reject { |_, v| v == "AAA" || v == "ZZZ" }
      end

      def get_other_names(datum, names_data)
        if is_array?(names_data) || (!names_data["Names"]["EntityName"].blank?)
          if names_data.is_a?(Hash)
            name_type = names_data["NameType"]["_attributes"]["Type"] if names_data["NameType"]
            if (name_type == "PrevLegal")
              datum[:previous_names] << {company_name: names_data["Names"]["EntityName"]}
            else
              datum[:alternative_names] << {company_name: names_data["Names"]["EntityName"], type: "trading", end_date: get_parse_date(names_data["ExpirationDate"])}.snap
            end
          else
            names_data.each {|name_data| get_other_names(datum, name_data)}
          end
        end
      end

      def is_array?(attribute)
        attribute.is_a?(Array)
      end

      def get_parse_date(date_value)
        Date.strptime(date_value, "%Y-%m-%d") rescue nil
      end

      def process_officer(datum, officer_info)
        titles = is_array?(officer_info["Title"]) ? officer_info["Title"] : [officer_info["Title"]]
      
        titles.snap.each do |title|
          officer_data = {other_attributes: {address: {}}}
          officer_data[:name] = (officer_info["Names"].key? ("EntityName")) ? officer_info["Names"]["EntityName"] : officer_info["Names"]["IndividualName"]
          officer_data[:type] = officer_info["Names"].key?("EntityName") ? "Company" : "Person"
          officer_data[:position] = format_status_label(title["_attributes"]["Type"]) if title["_attributes"]["Type"]
          officer_data[:other_attributes][:address] = extract_address(officer_info["Names"]["Address"])
          datum[:officers] << build_officer(officer_data)
        end
      end

      def build_officer(data)
        officer = {other_attributes: {address: {}}}
        officer[:name] = build_name(data[:name])
        officer[:position] = data[:position]
        officer[:other_attributes][:type] = data[:type]
        officer[:other_attributes][:address] = data[:other_attributes][:address]
        officer[:other_attributes][:email] = data[:other_attributes][:email]
        officer[:other_attributes][:telephone_number] = data[:other_attributes][:phone]
        officer[:other_attributes] = officer[:other_attributes].snap
        officer.snap
      end

      def build_name(name)
        if name.is_a?(String) # EntityName case
          name
        else # IndividualName case
          [
            name["FirstName"],
            name["MiddleName"],
            name["LastName"],
            name["Suffix"]
          ].compact.join(" ").squeeze(" ")
        end
      end

      def extract_address(address_info)
        return if address_info.blank?

        address_info = get_clean_address_hash(address_info)
        address = is_array?(address_info) ? address_info.find { |a| a.dig("AddressType", "_attributes", "Type") == "Mailing" } : address_info
        return if address.blank?

        street = [address["Address1"], address["Address2"]].compact.reject(&:blank?).join(", ")

        clean_address({
          street_address: street,
          locality: address["City"],
          region: address["StateOrProvince"],
          postal_code: address["PostalCode"],
          country: address["Country"]
        }.snap)
      end

      def get_domicile_data(datum, object)
        domicile_type = object["DomicileType"]["_attributes"]["Type"]
        if domicile_type == "Foreign"
          datum[:branch] = "F"
          state_value = object["State"]
          country_value = object["Country"]
          if state_value == country_value
            datum[:all_attributes][:jurisdiction_of_origin] = state_value
          elsif state_value == "OutOfCountry"
            datum[:all_attributes][:jurisdiction_of_origin] = country_value
          elsif state_value == "Undefined"
            datum[:all_attributes][:jurisdiction_of_origin] = ""
          else
            datum[:all_attributes][:jurisdiction_of_origin] = [state_value, country_value].compact.join(", ")
          end
          datum[:all_attributes][:jurisdiction_of_origin] = get_jurisdiction_of_origin(datum[:all_attributes][:jurisdiction_of_origin])
        end
      end

      def get_jurisdiction_of_origin(value)
        ((value.include? "AAA") || (value.include? "ZZZ")) ? value.gsub(/AAA|ZZZ|,/, '').squish : value.squish if value
      end

      def valid_address_type?(address)
        address["AddressType"] && ["PrincipalOffice", "Mailing"].include?(address["AddressType"]["_attributes"]["Type"])
      end

      def valid_address?(address)
        address.present? && address.snap.present?
      end

      def format_status_label(value)
        value.gsub(/([a-z])([A-Z])/, '\1 \2')
      end

      def get_names_data(datum, value)
        datum[:name] = value["EntityName"]
        if is_array?(value["Address"])
          value["Address"].select {|e| valid_address_type?(e) && valid_address?(e) }.each do |address|
            get_address(datum, address)
          end
        else
          get_address(datum, value["Address"]) if valid_address?(value["Address"])
        end
        datum[:telephone_number] = value["PhoneNumber"]
        datum[:all_attributes][:email] = value["EMail"]
        datum[:fax_number] = value["FaxNumber"] if value["FaxNumber"] && (value["FaxNumber"].exclude? "@")
      end

      def get_entity_dates_data(datum, value)
        date_type_values = is_array?(value) ? value.select{|e| (e["_attributes"]["Type"] == "DateOfIncorporation") || (e["_attributes"]["Type"] == "DateOfDissolution")} : value
        if date_type_values.is_a?(Hash)
          date_type = date_type_values["_attributes"]["Type"]
          if date_type.include? 'Incorporation'
            datum[:incorporation_date] = get_parse_date(date_type_values["_value"])
          else
            datum[:dissolution_date] = get_parse_date(date_type_values["_value"])
          end
        else
          date_type_values.each{|date_value_hash| get_entity_dates_data(datum, date_value_hash)}
        end
      end

      def get_stock_data(datum, object)
        total_share_data = is_array?(object["Stock"]) ? object["Stock"][0] : object["Stock"]
        datum[:total_shares][:share_class] = total_share_data["ShareClass"]
        datum[:total_shares][:number] = total_share_data["SharesIssued"].to_i
      end

      def get_registered_data(object)
        officer_data = {other_attributes: {address: {}}}
        officer_data[:name] = object["EntityName"] || object["IndividualName"]
        officer_data[:type] = object.key?("EntityName") ? "Company" : "Person"
        officer_data[:position] = "agent"
        officer_data[:other_attributes][:address] = extract_address(object["Address"])
        officer_data[:other_attributes][:email] = object["EMail"]
        officer_data[:other_attributes][:phone] = object["PhoneNumber"]
        officer_data
      end

      def get_states_info_data(datum, object)
        invalid_naics_codes = []
        if is_array?(object["StateSpecificXML"]["NAICSCodes"]["Code"])
          object["StateSpecificXML"]["NAICSCodes"]["Code"].snap.each do |industry_code_string|
            industry_code_value = industry_code_string.split("-").first.squish
            scheme_code = get_scheme_code(industry_code_value)
            if scheme_code.nil?
              invalid_naics_codes << {'code' => industry_code_value}
            else
              datum[:industry_codes] << {code: industry_code_value, code_scheme_id: scheme_code}
            end
          end
        else
          unless object["StateSpecificXML"]["NAICSCodes"]["Code"].blank?
            industry_code_value = object["StateSpecificXML"]["NAICSCodes"]["Code"].split("-").first.squish
            scheme_code = get_scheme_code(industry_code_value)
            if scheme_code.nil?
              invalid_naics_codes << {'code' => industry_code_value}
            else
              datum[:industry_codes] << {code: industry_code_value, code_scheme_id: scheme_code}
            end
          end
        end
        datum[:all_attributes][:invalid_naics_codes] = invalid_naics_codes unless invalid_naics_codes.empty?
        datum[:all_attributes][:business_classification_text] = object["StateSpecificXML"]["Purpose"]
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: 'us_ms',
          all_attributes: {},
          previous_names: [],
          alternative_names: [],
          headquarters_address: {},
          mailing_address: {},
          total_shares: {}, 
          identifiers: [],
          officers: [],
          industry_codes: [],
          registered_address: {}
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when "DocumentType"
          when "ReportYear"
          when "EntityInfo"
            object.each do |key, value|
              case key
              when "EntityType"
                datum[:company_type] = format_status_label(value["_attributes"]["Type"]) if value["_attributes"]["Type"]
                return nil if ["Sole Proprietorship", "Name Reservation"].include? datum[:company_type]

              when "Domicile"
                get_domicile_data(datum, value)
              when "EntityId"
                datum[:company_number] = value
                warn "COMPANY NUMBER: #{datum[:company_number]}"
              when "FEIN"
                identifier_hash = {"uid" => value, "identifier_system_code" => "us_fein"}.snap
                datum[:identifiers] << identifier_hash if identifier_hash[:uid]
              when "Alias"
                datum[:alternative_names] << {"company_name": value, "type": "alias"} unless value.blank?
              when "Names"
                get_names_data(datum, value)
              when "AdditionalName"
                get_other_names(datum, value) unless value.blank?
              when "EntityDates"
                get_entity_dates_data(datum, value["Date"]) if value["Date"]
              when "EntityStanding"
                current_status = CURRENT_STATUS[value["_attributes"]["Standing"]]
                datum[:current_status] = (current_status.blank?) ? format_status_label(value["_attributes"]["Standing"]) : current_status unless (value["_attributes"]["Standing"] == "Undefined")
              end
            end
          when "StockData"
            get_stock_data(datum, object)
          when "PartiesOnRecord"
            if object["Parties"].is_a?(Hash)
              process_officer(datum, object["Parties"])
            else
              object["Parties"].each { |officer_data| process_officer(datum, officer_data) }
            end
          when "RegisteredAgent"
            datum[:registered_address] = extract_address(object["Address"])
            next unless object.key?("EntityName") || object.key?("IndividualName")

            officer_data = get_registered_data(object)
            datum[:officers] << build_officer(officer_data)
          when "StateSpecificInfo"
            get_states_info_data(datum, object)
          when "RetrievedAt"
            datum[:retrieved_at] = object
          end
        end
        return nil if datum.blank?

        datum[:officers]&.delete_if { |officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/] }
        datum[:officers].snap
        datum[:officers] = datum[:officers].uniq
        datum[:all_attributes].snap
        datum[:headquarters_address] = clean_address(datum[:headquarters_address].snap)
        datum[:registered_address] = clean_address(datum[:registered_address].snap) if datum[:registered_address]
        datum[:mailing_address] = clean_address(datum[:mailing_address].snap)
        datum[:industry_codes] = datum[:industry_codes]&.uniq
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        return nil if datum[:name].blank?
        return nil if datum[:company_number].blank?
        datum.snap
        datum[:dissolution_date] = "" if (datum[:dissolution_date].blank?) || (datum[:current_status] == "Good Standing")
        datum
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end
