# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module Fr2CompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function

    def run
      start_time = Time.now.utc
      counter = 0
      input_data do |fetched_datums|
        yielded = false
        JSON.parse(IO.read(fetched_datums[fetched_datums.keys.first])).each do |fetched_datum|
          parsed_data = parse(fetched_datum, fetched_datums["retrieved_at"]) do |parsed_datum|
            yielded = true
            next if parsed_datum.blank?
            persist(parsed_datum)
            counter += 1
          end

          unless yielded
            parsed_data = [parsed_data] unless parsed_data.is_a?(Array)
            parsed_data.each do |parsed_datum|
              next if parsed_datum.blank?
              persist(parsed_datum)
              counter += 1
            end
          end
        end
      end
      { parsed: counter, parser_start: start_time, parser_end: Time.now.utc }
    end

    def parse(fetched_datum, retrieved_at)
      parsed_datum = {}
      parsed_datum['INPI_DATA'] = fetched_datum
      parsed_datum['RetrievedAt'] = retrieved_at
      parsed_datum
    rescue RuntimeError
      IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
      raise
    end
  end
end
