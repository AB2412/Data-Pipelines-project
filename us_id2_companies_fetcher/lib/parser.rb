# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsId2CompaniesFetcher
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
      BULK_SIZE = 10000

      def file_to_object(publish, base_directory)
        db_file = "#{base_directory}/dump.db"
        @db = SQLite3::Database.new(db_file, results_as_hash: true)
        if File.zero?(db_file)
          publish.each do |filename, file_location|
            content = File.read(file_location)
            modified_content = content.gsub('"', '')
            File.write(file_location, modified_content)

            warn "Unpacking file: #{filename}"
            command = "sqlite3 -separator '\t' -batch #{db_file} \".import #{file_location} #{filename}\""
            stdout, stderr, status = Open3.capture3(command)
            Open3.capture3("sqlite3 -batch #{db_file} '.read lib/indices.sql'")
            warn "Persisting file: #{file_location} to table #{filename}"
          end
        end

        bulk_corps_id = @db.execute('select distinct CONTROL_NO from FILING').map do |e|
          e['CONTROL_NO']
        end

        counter = bulk_corps_id.count/BULK_SIZE
        return nil if bulk_corps_id.blank?

        bulk_corps_id.each_slice(BULK_SIZE).each do |corporations_id|
          warn "Countdown : #{counter}"
          counter = counter - 1
          corporations_id_string = '"' + corporations_id.join('","') + '"'
          cdx_array = ['FILING', 'FILING_NAME', 'PARTY']
          cdx_data = {}
          cdx_array.each do |cdx|
            cdx_data[cdx] = load_to_hash(corporations_id_string, cdx, 'CONTROL_NO')
          end
          corporations_id.each do |corporation_id|
            input = publish.map do |key, value|
              { key => cdx_data[key][corporation_id]} if cdx_array.include? key
            end.reject(&:blank?).inject(&:update)
            yield(input.snap)
          end
        end
      end

      def load_to_hash(corporations_id_string, table_name, key)
        hash = {}
        @db.execute("select * from #{table_name} where #{key} IN (#{corporations_id_string})").map do |e|
          if hash[e[key]]
            hash[e[key]].push(e)
          else
            hash[e[key]] = [e]
          end
        end
        hash
      end
    end

    def parse(payload)
      SQLiteParser.file_to_object(payload['body'], payload['base_directory']) do |entry|
        yield(entry.merge({ 'RetrievedAt' => payload['sampled_at'] }))
      end
    end
  end
end
