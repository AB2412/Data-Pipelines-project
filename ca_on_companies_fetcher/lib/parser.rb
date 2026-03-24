# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module CaOnCompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function

    def file_to_object(publish)
      @entries = []
      publish.each do |name, file_path|
        warn "Started processing file: #{file_path}"
        File.readlines(file_path).each do |line|
          @entries.push({'data' => JSON.parse(line)})
        end
      end
      @entries
    end

    def parse(payload)
      entries = file_to_object(payload['body'])
      entries.map do |entry|
        entry.merge({ 'RetrievedAt' => payload['sampled_at'] })
      end
    end
  end
end
