# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsMt2CompaniesFetcher
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

    module SQLiteParser
      module_function

      def file_to_object(publish, base_directory)
        db_file = "#{base_directory}/dump.db"
        db = SQLite3::Database.new(db_file, results_as_hash: true)
        if File.zero?(db_file)
          publish.each do |filename, file_location|
            csv_content = []
            File.foreach(file_location).with_index do |line, index|
              csv_content << line unless index < 3
            end
            csv_content = csv_content.join("")
            tempfile = Tempfile.new(['csv', '.csv'], base_directory)
            tempfile.write(csv_content)
            tempfile.close
            path = tempfile.path
            warn "Persisting file: #{file_location} to table #{filename}"
            command_output = Open3.capture3("sqlite3 -separator ',' -batch #{db_file} '.import #{path} #{filename.split("-").first.downcase}'")
            tempfile.close!
          end
        end

        db.execute('select * from entityreport').each do |data_hash|
          yield(data_hash)
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
