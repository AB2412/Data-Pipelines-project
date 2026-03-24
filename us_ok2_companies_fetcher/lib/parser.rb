# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

module UsOk2CompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function

    def run
      start_time = Time.now.utc
      @counter = 0
      input_data do |fetched_datum|
        @yielded = false
        file_records = fetch_file_records(fetched_datum[fetched_datum.keys.first])
        entity_records = @db.execute("select * from ENTITY_INFORMATION")
        entity_records.each do |entity_record|
          parsed_data = parse(entity_record, fetched_datum['retrieved_at']) do |parsed_datum|
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
      end
      { parsed: @counter, parser_start: start_time, parser_end: Time.now.utc }
    end

    def fetch_file_records(file)
      sections = Hash.new { |hash, key| hash[key] = { headers: nil, rows: [] } }
      file_path = file.split("/")[0...-1].join("/")
      previous_prefix = nil
      File.open(file, "r").each_line.lazy.each_with_index do |line, line_index|
        $stderr.puts "LINE: #{line_index}"
        line.chomp! # Remove newline characters
        line = line.strip.force_encoding("ISO-8859-1").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        get_prefix = line[0..1]
        prefix = (get_prefix.starts_with? "~1") ? "01" : (get_prefix.to_i == 0) ? previous_prefix : get_prefix

        if previous_prefix && (prefix != previous_prefix)
          flush_to_temp_file(sections, file_path)
          sections.clear
        end
        next if PREFIXES.exclude? prefix
        break if prefix == "18"

        data = line.split("~")
        # Handle the headers and rows
        if sections[prefix][:headers].nil?
          sections[prefix][:headers] = data
        else
          # Avoid building a large hash for each line; write out or yield as needed
          row_hash = sections[prefix][:headers].zip(data).to_h
          sections[prefix][:rows] << row_hash
        end
        # Periodically flush or process data to reduce memory usage
        if sections[prefix][:rows].size == DATA_ARRAY_LIMIT
          flush_to_temp_file(sections, file_path)
          sections[prefix][:rows].clear
        end
        previous_prefix = prefix
        $stderr.puts "PREVIOUS_PREFIX = #{previous_prefix}"
      end
      dump_csvs_into_database(file_path)
    end

    def dump_csvs_into_database(file_path)
      @db_file = "#{file_path}/dump.db"
      @db = SQLite3::Database.new(@db_file, results_as_hash: true)
      Dir.glob("#{file_path}/temp_*.csv") do |filename|
        $stderr.puts "Inserting: #{filename}"
        tablename = TABLE_NAMES[File.basename(filename, '.*').sub('temp_', '')]
        command_output = Open3.capture3("sqlite3 -separator ',' -batch #{@db_file} '.import #{filename} #{tablename}'")
        File.delete(filename)
      end
      command_output = Open3.capture3("sqlite3 -batch #{@db_file} '.read lib/indices.sql'")
    end

    def flush_to_temp_file(sections, file_path)
      sections.each do |prefix, content|
        temp_file = "#{file_path}/temp_#{prefix}.csv"
        CSV.open(temp_file, "a+") do |csv|
          if File.zero?(temp_file) && content[:headers]
            csv << content[:headers]
          end
          content[:rows].each do |row|
            csv << row.values
          end
        end
      end
    end

    def filter_records_by_entity_record(table_name, key, record)
      @db.execute("select * from #{table_name} where #{key} = #{record[key]}") unless record[key].blank?
    end

    def fetch_join_records(records, table_name, key, already_fetched_records)
      records.each do |record|
        next if record[key].blank?
        matched_record = filter_records_by_entity_record(table_name, key, record)&.first
        next if already_fetched_records.include? matched_record[key]
        already_fetched_records << matched_record[key]
        records << matched_record
      end
      [records, already_fetched_records]
    end

    def parse(entity_record, retrieved_at)
      parsed_datum = {}
      $stderr.puts "PARSED: #{entity_record["FILING_NUMBER"]}"
      parsed_datum['01'] = entity_record
      parsed_datum['02'] = filter_records_by_entity_record(TABLE_NAMES['02'], "ADDRESS_ID", entity_record)
      parsed_datum['03'] = filter_records_by_entity_record(TABLE_NAMES['03'], "FILING_NUMBER", entity_record)
      parsed_datum['04'] = filter_records_by_entity_record(TABLE_NAMES['04'],"FILING_NUMBER", entity_record)
      address_ids = (parsed_datum['02'].blank?) ? [] : parsed_datum['02'].map{|s| s["ADDRESS_ID"]}
      parsed_datum['03'], address_ids = fetch_join_records(parsed_datum['03'], TABLE_NAMES['02'], "ADDRESS_ID", address_ids)
      parsed_datum['04'], address_ids = fetch_join_records(parsed_datum['04'], TABLE_NAMES['02'], "ADDRESS_ID", address_ids)
      parsed_datum['05'] = filter_records_by_entity_record(TABLE_NAMES['05'], "FILING_NUMBER", entity_record)
      parsed_datum['07'] = filter_records_by_entity_record(TABLE_NAMES['07'], "FILING_NUMBER", entity_record)
      parsed_datum['17'] = filter_records_by_entity_record(TABLE_NAMES['17'], "FILING_NUMBER", entity_record)
      parsed_datum['RetrievedAt'] = retrieved_at
      parsed_datum
    rescue RuntimeError
      IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
      raise
    end
  end
end
