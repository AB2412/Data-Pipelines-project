# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_parser'
require 'openc_bot/helpers/dates'
require 'digest/sha1'
require 'csv'
require 'open3'

# change the JurisdictionCode with the appropriate value, i.e. UsGa, Sg, UsTx, Ro
module IlCompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend OpencBot::Helpers::Dates

    module_function

    module SQLiteParser
      module_function

      def file_to_object(publish, base_directory)
        db_file = "#{base_directory}/dump.db"
        db = SQLite3::Database.new(db_file, results_as_hash: true)
        if File.zero?(db_file)
          company_name_map = {"ICA_PARTNERSHIP"=> "Partnerships_number", "ICA_COMPANIES"=> "Company_number"}
          publish.each do |filename, file_location|
            warn "Unpacking file: #{filename}"
            if filename == "ICA_PARTNERSHIP"
              new_names = ["Partnerships_number", "Partnership_name", "Partnership_name_english", "Type_of_corporation", "Corporation_status", "Date_of_incorporation", "Settlement", "Street", "House_number", "Postal_Code", "P.O", "Country", "at"]
              CSV.open("#{base_directory}/CUSTOM_#{filename}.csv", "w", write_headers: true, headers: new_names) do |csv|
                CSV.foreach("#{file_location}", headers: :first_row) do |row|
                  csv << row
                end
              end
            else
              new_names = ["Company_number", "Company_name", "Company_name_english", "Type_of_corporation", "Company_Status", "Company_description", "Purpose_of_company", "Date_of_incorporation", "Govermental_company", "Limitations", "Violation", "Last_year_annual_report", "City_name", "Street_name", "House_number", "Postal_Code", "P.O", "Country", "at", "Sub_Status"]
              CSV.open("#{base_directory}/CUSTOM_#{filename}.csv", "w", write_headers: true, headers: new_names) do |csv|
                CSV.foreach("#{file_location}", headers: :first_row) do |row|
                  csv << row
                end
              end
            end
            warn "persisting file: #{filename}"
            command_output = Open3.capture3("sqlite3 -separator ',' -batch #{db_file} '.import #{base_directory}/CUSTOM_#{filename}.csv #{filename}'")

            company_uids = db.execute("select \"#{company_name_map[filename]}\" from #{filename}").map { |e| e["#{company_name_map[filename]}"] }
            return nil if company_uids.blank?

            company_uids.each do |uid|
              input = {}
              input[filename] = db.execute("SELECT * FROM  \"#{filename}\" WHERE \"#{company_name_map[filename]}\" LIKE ?", uid)
              yield(input)
            end
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

