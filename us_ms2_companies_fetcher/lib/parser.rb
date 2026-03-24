# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsMs2CompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function

    def run
      start_time = Time.now.utc
      @counter = 0
      input_data do |fetched_datum|
        @yielded = false
        parsed_data = parse(fetched_datum) do |parsed_datum|
          @yielded = true
          next if parsed_datum.blank?
          persist(parsed_datum)
          @counter += 1
        end

        unless @yielded
          parsed_data = [parsed_data] unless parsed_data.is_a?(Array)
          parsed_data.each do |parsed_datum|
            next if parsed_datum.blank?
            persist(parsed_datum)
            @counter += 1
          end
        end
      end
      { parsed: @counter, parser_start: start_time, parser_end: Time.now.utc }
    end

    def xml_to_hash(node)
      return node.text.strip if node.element_children.empty?

      hash = {}
      node.element_children.each do |child|
        key = child.name
    
        # If this child already exists (i.e., multiple same-named tags), convert to array
        if hash[key]
          hash[key] = [hash[key]] unless hash[key].is_a?(Array)
          hash[key] << xml_to_hash(child)
        else
          hash[key] = xml_to_hash(child)
        end
    
        # Include attributes if any
        unless child.attributes.empty?
          if hash[key].is_a?(Array)
            # Update the last element of the array
            hash[key][-1] = { "_value" => hash[key][-1] } if hash[key][-1].is_a?(String)
            hash[key][-1]["_attributes"] = child.attributes.transform_values(&:value)
          else
            # hash[key] is a hash
            hash[key] = { "_value" => hash[key] } if hash[key].is_a?(String)
            hash[key]["_attributes"] = child.attributes.transform_values(&:value)
          end
        end
      end
      hash
    end

    def parse(payload)
      parsed_data = []
      xml_file_path = payload.keys.select{|f| f.include? 'profiles_'}.first
      xml_content = File.read(payload[xml_file_path])
      doc = Nokogiri::XML(xml_content)
      document_records = doc.xpath('//Profiles/Document')
      document_records.each do |record|
        parsed_datum = {}
        data_hash = xml_to_hash(record)
        parsed_datum["Header"] = data_hash["Header"]
        data_hash["Record"].each do |key, value|
          parsed_datum[key] = value
        end
        parsed_datum["RetrievedAt"] = payload["retrieved_at"]
        parsed_data << parsed_datum
      end
      parsed_data
    end
  end
end
