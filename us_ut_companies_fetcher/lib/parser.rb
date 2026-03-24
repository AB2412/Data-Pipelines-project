# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsUtCompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function
    BULK_SIZE = 5000

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

    module SQLiteParser
      module_function

      def file_to_object(publish, base_directory)
        db_file = "#{base_directory}/dump.db"
        db = SQLite3::Database.new(db_file, results_as_hash: true)

        if File.zero?(db_file)
          publish.each do |filename, file_location|
            warn "Persisting file: #{file_location} to table #{filename}"
            command_output = Open3.capture3("sqlite3 -separator ',' -batch #{db_file} '.import #{base_directory}/#{filename}.csv #{filename}'")
          end
        end
        uids = db.execute("select \"#{'Entity ID'}\" from busentity").map { |e| e["Entity ID"] }
        return nil if uids.blank?

        uids.uniq.each_slice(BULK_SIZE).each do |bulk_uid|
          query_string = '"' + bulk_uid.join('","') + '"'
          company_data = {}
          publish.each_key.map do |key|
            hash = {}
            identifier = "Entity ID"
            dat = db.execute("select * from #{key} where \"#{identifier}\" in (#{query_string})")
            dat.each do |e|
              if hash[e[identifier]]
                hash[e[identifier]].push(e)
              else
                hash[e[identifier]] = [e]
              end
            end
            company_data[key] = hash
          end

          bulk_uid.each do |uid|
            input = publish.each_key.map do |key|
              { key => company_data[key][uid] }
            end.inject(&:update)
            yield(input)
          end
        end
      end
    end

    def parse(payload)
      SQLiteParser.file_to_object(payload['body'], payload['base_directory']) do |entry|
        yield(entry.merge({ 'RetrievedAt' => payload['sampled_at'] }))
      end
    end
  end
end
