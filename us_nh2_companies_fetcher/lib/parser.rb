# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsNh2CompaniesFetcher
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

      def get_headers(filename)
        case filename
        when "BusinessDetails.csv"
          BUSINESS_DETAIL
        when "BusinessAddress.csv"
          BUSINESS_ADDRESS
        when "Filing.csv"
          FILING
        when "PreviousBusinessNames.csv"
          PREVIOUS_BUSINESS_NAMES
        when "PrincipalPurpose.csv"
          PRINCIPAL_PURPOSE
        when "Principals.csv"
          PRINCIPALS
        when "RegisteredAgent.csv"
          REGISTERED_AGENT
        when "Stock.csv"
          STOCK
        end
      end

      def clean_record(line)
        new_line = line.gsub(/(?<=[^,])"(?=[^,])/, '|') # find double quotes (") that are surrounded by non-comma ([^,]) characters.
        new_line = new_line.gsub(/(?<=,)""/, '%') # Finds "" (double quotes appearing twice) immediately after a comma (,).
        new_line = new_line.gsub(/(?<=[a-zA-Z]),"/, ',|') # It finds ," (comma + double quote) ONLY when the comma is after a letter.
        new_line = new_line.gsub(/"(?=, )/, '|') # It finds " (a double quote) ONLY when it is directly followed by ,  (comma + space).
        parsed_line = CSV.parse_line(new_line)
        parsed_line.map!{|s| s && s.gsub('|', '"').gsub('%', '')}
      end

      def file_to_object(publish, base_directory)
        db_file = "#{base_directory}/dump.db"
        db = SQLite3::Database.new(db_file, results_as_hash: true)
        if File.zero?(db_file)
          publish.each do |filename, file_location|
            warn "Unpacking file: #{filename}"
            headers = get_headers(filename)
            CSV.open("#{base_directory}/Custom_#{filename}", 'wb', write_headers: true, headers: headers , encoding: 'utf-8') do |csv|
              File.open(file_location, encoding: 'ISO-8859-1:utf-8', invalid: :replace, undef: :replace).each("\n").with_index(1) do |line, line_number|
                warn "INDEX: #{line_number}"

                if file_location.exclude? "weekly"
                  line = line.gsub("\u0000", '') # Remove null bytes
                  line = line.gsub(/\A\xEF\xBB\xBF/, '') # Remove BOM (Byte Order Mark) if present
                  line = line.gsub(/\Aÿþ/, '') # Remove UTF-16 BOM if present
                end
                # Remove leading/trailing whitespace
                line.strip!
                # Skip empty lines
                next if line.blank?

                begin
                  if file_location.include? "weekly"
                    parsed_line = CSV.parse_line(line, liberal_parsing: true, col_sep: "|")
                  else
                    parsed_line = CSV.parse_line(line) rescue nil
                    parsed_line = clean_record(line) if parsed_line == nil
                  end
                  csv << parsed_line
                rescue CSV::MalformedCSVError
                  malformed_file = base_directory.split("/")[1..].join("_")
                  IO.write("tmp/#{malformed_file}_malformed.txt", "#{line}\n", mode:"a")
                  warn "Malformed line: #{line}, filename: #{filename}"
                end
              rescue StandardError => e
                warn "Error on line #{line}"
                raise e
              end
            end
            warn "Persisting file: #{file_location} to table #{filename}"
            command_output = Open3.capture3("sqlite3 -separator ',' -batch #{db_file} '.import #{base_directory}/Custom_#{filename} #{filename.gsub(".csv", "")}'")
          end
          command_output = Open3.capture3("sqlite3 -batch #{db_file} '.read lib/indices.sql'")
        end
        uids = db.execute("select BusinessID from BusinessDetails").map{|e| e["BusinessID"]}
        return nil if uids.blank?

        uids.uniq.each_slice(BULK_COUNT).each do |bulk_uid|
          query_string = '"' + bulk_uid.join('","') + '"'
          company_data = {}
          publish.each_key.map do |key|
            hash = {}
            table_name = File.basename(key, '.*')
            db.execute("select * from #{table_name} where BusinessID in (#{query_string})").each do |e|
              load_to_hash(e, hash, 'BusinessID')
            end
            company_data[key] = hash
          end
          bulk_uid.each do |uid|
            warn "PARSED: #{uid}"
            input = publish.each_key.map do |key|
              { key.gsub(".csv","") => company_data[key][uid] }
            end.inject(&:update)
            yield(input) unless input.values.all? nil
          end
        end
      end

      def load_to_hash(data, hash, key)
        if hash[data[key]]
          hash[data[key]].push(data)
        else
          hash[data[key]] = [data]
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
