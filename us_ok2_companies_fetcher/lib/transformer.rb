# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module UsOk2CompaniesFetcher
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

      def parse_date(date_string)
        ((date_string == "00/00/0000") || (date_string.match?(%r{^\d{2}/\d{2}/9999$}))) ? nil : Date.strptime(date_string, "%m/%d/%Y").strftime("%Y-%m-%d") rescue nil
      end

      def get_zip_code(zip_code, zip_extension)
        ((zip_code.blank?) || (zip_extension.blank?)) ? "#{zip_code}-#{zip_extension}".gsub("-","").squish : "#{zip_code}-#{zip_extension}".squish
      end

      def get_address(address_hash)
        {
          street_address: "#{address_hash["ADDRESS2"]} #{address_hash["ADDRESS1"]}".squish,
          locality: address_hash["CITY"],
          region: address_hash["STATE"],
          postal_code: get_zip_code(address_hash["ZIP_CODE"], address_hash["ZIP_EXTENSION"]),
          country: address_hash["COUNTY"]
        }
      end

      def get_jurisdiction_of_origin(foreign_country, foreign_state)
        [foreign_state, foreign_country].reject(&:blank?).join(' ').presence
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: 'us_ok',
          all_attributes: {},
          registered_address: {},
          total_shares: {},
          filings: [],
          officers: [],
          alternative_names: [],
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when "01"
            datum[:company_number] = object["FILING_NUMBER"]
            return nil if object["01"].blank?
            $stderr.puts "COMPANY_NUMBER: #{datum[:company_number]}"
            datum[:current_status] = STATUS_ID[object["STATUS_ID"]]
            $stderr.puts "SKIPPING: #{datum[:company_number]} CORP_ID: #{object["CORP_TYPE_ID"]}" if EXCLUDE_CORP_TYPES.include? object["CORP_TYPE_ID"]
            return nil if EXCLUDE_CORP_TYPES.include? object["CORP_TYPE_ID"]

            datum[:company_type] = CORP_TYPE_ID[object["CORP_TYPE_ID"]]
            return nil if datum[:company_type].blank?
            datum[:branch] = (datum[:company_type].include? "Foreign") ? "F" : nil
            datum[:name] = object["NAME"]
            datum[:incorporation_date] = parse_date(object["CREATION_DATE"])
            datum[:dissolution_date] = (["1","11"].exclude? object["STATUS_ID"]) ? parse_date(object["EXPIRATION_DATE"]) : nil
            datum[:all_attributes][:jurisdiction_of_origin] = get_jurisdiction_of_origin(object["FOREIGN_COUNTRY"], object["FOREIGN_STATE"])
            datum[:all_attributes][:foreign_formation_date] = parse_date(object["FOREIGN_FORMATION_DATE"])

            unless input["02"].nil?
              address_records = input["02"].select{|s| s["ADDRESS_ID"] == object["ADDRESS_ID"]}
              address_records.each do |address_record|
                datum[:registered_address] = get_address(address_record)
              end
            end
          when "02"
          when "03", "04"
            object.each do |obj|
              officer_position = (legend == "03") ? "agent" : obj["OFFICER_TITLE"]
              address = {}
              if obj["BUSINESS_NAME"].blank? && !obj["AGENT_FIRST_NAME"].blank? || !obj["FIRST_NAME"].blank?
                officer_type = "Person"
                if legend == "03"
                  officer_name = "#{obj["AGENT_FIRST_NAME"]} #{obj["AGENT_MIDDLE_NAME"]} #{obj["AGENT_LAST_NAME"]}".squish
                else
                  officer_name = "#{obj["FIRST_NAME"]} #{obj["MIDDLE_NAME"]} #{obj["LAST_NAME"]}".squish
                end
              else
                officer_type = "Company"
                officer_name =  obj["BUSINESS_NAME"]
              end
              officer = {
                name: officer_name, position: officer_position, start_date: parse_date(obj["CREATION_DATE"]),
                end_date: parse_date(obj["INACTIVE_DATE"]),
                other_attributes: {address: {}, type: officer_type}
              }
              address_records = object.select{|s| s["ADDRESS_ID"] == obj["ADDRESS_ID"] && s.keys.first == "02"}
              address_records.each do |address_record|
                address = clean_address(get_address(address_record).snap)
                unless address.blank?
                  officer[:other_attributes][:address] = address
                end
              end
              officer[:other_attributes].snap
              datum[:officers] << officer.snap unless officer[:name].nil?
            end
          when "05"
            object.each do |obj|
              next if (obj["NAME_TYPE_ID"] == "1")
              alternative_names_hash = {}
              alternative_names_hash[:company_name] = obj["NAME"]
              alternative_names_hash[:type] = NAME_TYPE_ID_MAPPING[obj["NAME_TYPE_ID"]]
              next if alternative_names_hash[:type].blank? || alternative_names_hash[:company_name].blank?
              alternative_names_hash[:start_date] = parse_date(obj["CREATION_DATE"])
              alternative_names_hash[:end_date] = parse_date(obj["INACTIVE_DATE"])
              datum[:alternative_names] << alternative_names_hash.snap
            end
          when "07"
            object.each do |obj|
              datum[:total_shares][:share_class] = STOCK_TYPE_ID[obj["STOCK_TYPE_ID"]]
              datum[:total_shares][:number] = obj["SHARE_VOLUME"].to_i
            end
          when "17"
            object.each do |obj|
              filing = {}
              filing[:uid] = obj["DOCUMENT_NUMBER"]
              filing[:title] = FILING_TYPE.select{|e| e["FILING_TYPE_ID"] == obj["FILING_TYPE_ID"]}.first["FILING_TYPE"] rescue nil
              #changing start_date to date as per schema
              filing[:date] = parse_date(obj["ENTRY_DATE"])
              filing[:end_date] = parse_date(obj["INACTIVE_DATE"])
              next if filing[:date].blank? || filing[:title].blank?
              datum[:filings] << filing.snap if valid_filing?(filing)
            end
          when 'RetrievedAt'
            datum[:retrieved_at] = object
          else
            raise "Unhandled legend: #{legend}"
          end
        end
        return nil if datum.blank?
        datum[:officers]&.delete_if { |officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/] }
        datum[:all_attributes].snap
        datum[:registered_address] = clean_address(datum[:registered_address].snap)
        datum[:total_shares] = nil if datum[:total_shares][:number].blank?
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
