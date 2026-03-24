# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsNmCompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function

    def run
      start_time = Time.now.utc
      counter = 0
      File.open(output_file_location, 'a') do |f|
        input_data do |fetched_datum|
          yielded = false
          result = parse(fetched_datum) do |parsed_datum|
            next if parsed_datum.blank?

            f.puts parsed_datum.to_json
            counter += 1
            yielded = true
          end
          if yielded == false
            result.each do |parsed_datum|
              next if parsed_datum.blank?

              f.puts parsed_datum.to_json
              counter += 1
            end
          end
        end
      end
      { parsed: counter, parser_start: start_time, parser_end: Time.now.utc }
    end

    def parse(payload)
      payload.map do |_key, value|
        value.merge({ 'RetrievedAt' => Time.now.utc.iso8601 })
      end
    end
  end
end
