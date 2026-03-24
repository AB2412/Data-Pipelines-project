# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

# change the JurisdictionCode with the appropriate value, i.e. UsGa, Sg, UsTx, Ro
module IlCompaniesFetcher
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

      def handle_address(addr_string)
        rs = ''
        if addr_string['street']
          if addr_string['at'] && (addr_string['at'].include? '~')
            if (addr_string['at'].start_with? '~') && (addr_string['at'].end_with? '~')
              tp = addr_string['at'].gsub('~', '')
              rs = "#{addr_string['house_number']} #{tp}\" ,#{addr_string['street']}\""
            else
              rs = "#{addr_string['house_number']} #{addr_string['at'].gsub('~', '"')} ,#{addr_string['street']}"
            end
          elsif addr_string['at']
            rs = "#{addr_string['house_number']} #{addr_string['at']} ,#{addr_string['street']}"
          else
            rs = "#{addr_string['house_number']} #{addr_string['street']}"
          end
        else
          if addr_string['at'] && (addr_string['at'].include? '~')
            rs = "#{addr_string['house_number']} #{addr_string['at'].gsub('~', '"')}"
          else
            rs = "#{addr_string['house_number']} #{addr_string['at']}"
          end
        end
        rs = rs.gsub(' ,', '') if rs.end_with? ' ,'
        rs.gsub('  ,', '')
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: 'il',
          all_attributes: {},
          alternative_names: [],
          registered_address: {},
          mailing_address: {},
          filings: [],
          officers: [],
        }

        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when 'ICA_COMPANIES'
            company = { company_type: Array.new() }
            addr = { street_name: {}}
            object.last.snap.each do |key, value|
              case key
              when 'Company_number'
                datum[:company_number] = value
              when 'Company_name'
                datum[:name] = value.gsub("~", '"')
              when "Company_name_english"
                datum[:alternative_names]  << { company_name: value, type: "legal", language: "en" }
              when 'Type_of_corporation'
                company[:company_type].insert(0, value)
              when 'Company_Status'
                translation = {"פעילה"=> "Active", "מחוקה"=> "Removed", "מחוסלת מרצון"=> "Voluntary dissolved", "בפרוק מרצון"=> "Liquidated", "בפרוק ע~י בימ~ש"=> "Dissolution by court", "חיסול ע~י בימ~ש"=> "In Liquidation by court", "מחוסלת עקב מיזוג"=> "Dissolved due to merger", "פעילה זמנית"=> "Temporarily Active", "נגרעה מהמרשם"=> "Removed from the register", "פעילה/בפירוק - הליך פשרה או הסדר/פירוק זמני"=> "Active/In dissolution - Compromise procedure or temporary arrangement/dissolution", "פעילה/בפירוק - בכינוס נכסים"=> "Active/in liquidation - in receivership"}
                datum[:current_status] = "#{translation[value]} (#{value.gsub("~", '"')})"
              when 'Company_description'
                datum[:all_attributes][:business_classification_text] = value
              when 'Purpose_of_company'
                datum[:all_attributes][:purpose] = value
              when 'Date_of_incorporation'
                datum[:incorporation_date] = Date.parse(value).strftime("%Y-%m-%d")
              when 'Govermental_company'
                company[:company_type].insert(0, value)
              when 'Limitations'  
                company[:company_type].insert(1, value)
              when 'Violation'
                datum[:all_attributes][:violation] = value
              when 'Last_year_annual_report'
                datum[:all_attributes][:latest_annual_report] = value
              when 'City_name'
                datum[:registered_address][:locality] = value
              when 'Street_name'
                addr[:street_name]['street'] = value
              when 'House_number'
                addr[:street_name]['house_number'] = value
              when 'Postal_Code'
                datum[:registered_address][:postal_code] = value
              when 'Country'
                datum[:registered_address][:country] = value
              when 'at'
                addr[:street_name]['at'] = value
              when 'Sub_Status'
                datum[:all_attributes][:sub_status] = value
              end
            end

            unless addr[:street_name].blank?
              datum[:registered_address][:street_address] = handle_address(addr[:street_name])
            end

            types = {"חוץ חברה פרטית"=> "Foreign Company", "חוץ חברה פרטית"=> "Foreign Unlimited Company", "חוץ חברה פרטית"=> "Foreign Limited Company", "ישראלית חברה אגח"=> "Bond Limited Company (Governmental Company)", "ישראלית חברה אגח"=> "Bond Limited Company", "ישראלית חברה פרטית"=> "Private Unlimited Company (Governmental Company)", "ישראלית חברה פרטית"=> "Private Limited Company (Governmental Company)", "ישראלית חברה פרטית"=> "Private Company", "ישראלית חברה פרטית"=> "Private Unlimited Company", "ישראלית חברה פרטית"=> "Private Limited Company", "ישראלית חברה ציבורית"=> "Public Limited Company (Governmental Company)", "ישראלית חברה ציבורית"=> "Public Unlimited Company", "ישראלית חברה ציבורית"=> "Public Limited Company"}
            datum[:company_type] = "#{types[company[:company_type][2]]} (#{company[:company_type].snap.join(' - ').strip})"

          when 'ICA_PARTNERSHIP'
            addr = { street_name: {}}
            object.last.snap.each do |key, value|
              case key
              when "Partnerships_number"
                datum[:company_number] = value
              when "Partnership_name"
                datum[:name] = value.gsub("~", '"')
              when "Partnership_name_english"
                datum[:alternative_names]  << { company_name: value, type: 'legal', language: 'en' }
              when "Type_of_corporation"
                types = {"ישראלית כללית"=> "General Partnership", "ישראלית מוגבלת"=> "Limited Partnership", "חו~ל שותפות חו~ל מהסבה"=> "Foreign Joint Partnership", "חו~ל מוגבלת"=> "Foreign Limited Company", "חו~ל כללית"=> "Foreign General Company"}
                datum[:company_type] = "#{types[value]} (#{value.gsub("~", '"')})"
              when "Corporation_status"
                translation = {"פעילה"=> "Active", "מחוקה"=> "Removed", "שותפות מחוקה מרצון"=> "Voluntary deleted partnership", "פורקה מרצון"=> "Voluntarily disbanded", "מחוסלת מרצון"=> "Voluntary dissolved", "בפרוק ע~י בימ~ש"=> "Dissolution by court", "שותפות מחוקה על ידי בית משפט"=> "Struck down by court", "פעילה זמנית"=> "Temporarily Active", "בפרוק מרצון": "Liquidated", "פורקה ע~י בימ~ש"=> "Dissolved by court", "חיסול ע~י בימ~ש"=> "In Liquidation by court", "מחוסלת עקב מיזוג"=> "Dissolved due to merger"}
                datum[:current_status] = "#{translation[value]} (#{value.gsub("~", '"')})"
              when "Date_of_incorporation"
                datum[:incorporation_date] = Date.parse(value).strftime("%Y-%m-%d")
              when "Settlement"
                datum[:registered_address][:locality] = value
              when "Street"
                addr[:street_name]['street'] = value
              when "House_number"
                addr[:street_name]['house_number'] = value
              when "Postal_Code"
                datum[:registered_address][:postal_code] = value
              when "Country"
                datum[:registered_address][:country] = value
              when "at"
                addr[:street_name]['at'] = value
              end
            end

            unless addr[:street_name].blank?
              datum[:registered_address][:street_address] = handle_address(addr[:street_name])
            end
          when 'RetrievedAt'
            datum[:retrieved_at] = object
          else
            raise "Unhandled legend: #{legend}"
          end
        end
        return nil if datum.blank?

        if datum[:registered_address][:street_address] == nil && datum[:registered_address][:postal_code] == nil
          if datum[:registered_address][:locality] == nil && datum[:registered_address][:country] != nil
            datum.delete(:registered_address)
          elsif datum[:registered_address][:locality] != nil && datum[:registered_address][:country] == nil
            datum.delete(:registered_address)
          end
        end

        bad_data = [";", " .", "'", "`", ",", "n~ra", "na~ra", " LTD", "."]
        if datum[:alternative_names].length != 0
          datum[:alternative_names][0][:company_name].gsub!(/\s+/, " ")
          bad_data.each do |bad|
            datum[:alternative_names][0][:company_name] = datum[:alternative_names][0][:company_name].gsub(bad, "")
          end
          datum[:alternative_names][0][:company_name].strip!
          if datum[:alternative_names][0][:company_name].length <= 1 then datum.delete(:alternative_names) end
        end
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
