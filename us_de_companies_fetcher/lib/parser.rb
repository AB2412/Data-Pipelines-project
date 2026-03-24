require 'openc_bot/helpers/pseudo_machine_parser'
require 'stringio'
require 'csv'

module UsDeCompaniesFetcher
  module Parser
    extend OpencBot::Helpers::PseudoMachineParser
    extend self

    def company_type_row?(row)
      row.reject{|s| s == nil || s == ""}.count == 1 && row[0].scan(/^\s?\d+ - /).count == 0
    end

    def get_agent_info(csv_data, start_index)
      row_data = []
      csv_data[start_index..-1].each_with_index do |row, index_no|
        next if row[0] == nil || (row[0].scan(/^\s?\d+ - /).count == 0)
        row_data << row
        start_index+=1
        while true
          break if csv_data[start_index+index_no][0] == 'NAME'
          row_data << csv_data[start_index+index_no]
          start_index+=1
        end
        row = row_data.flatten.reject{|s| s == nil || s == ""}
        return [row, start_index+index_no]
      end
      [row_data, nil]
    end

    def get_company_details(csv_data, start_index)
      headers = csv_data[start_index].reject{|header| header == "" || header == nil}
      company_data = []

      while true
        start_index +=1
        row = csv_data[start_index]
        break if row == nil || row[0] == nil || row[0] == "" || company_type_row?(row)
        data_hash = {}
        headers.each_with_index do |header, header_index|
          data_hash["Company_#{header.gsub(' ', '_')}"] = row[header_index]
        end
        company_data << data_hash
      end
      [company_data, start_index]
    end

    def parse_agent(row)
      agent_info = {}
      agent_headers = ["officer_uid", "officer_name", "officer_address", "company_type"]

      if row.count == 2
        data_array = row[0].split(' - ')
        agent_info["officer_uid"] = data_array[0].strip
        agent_info["officer_name"] = data_array[1].strip
        agent_info["officer_address"] = data_array[2..-1].join(' - ').strip
      else
        officer_name    =    []
        officer_address =    []
        officer_name_complete = false

        row[0...-1].each_with_index do |row_column, column_index|
          data_array = row_column.split(' - ')
          if column_index == 0
            agent_info["officer_uid"] = data_array[0].strip
            officer_name << data_array[1]
            if data_array.count > 2
              officer_name_complete = true
              officer_address << data_array[2..-1].join(' - ')
            end
          else
            if officer_name_complete == false
              officer_name << ",#{data_array[0]}"
              if data_array.count > 1
                officer_name_complete = true
                officer_address << data_array[1..-1].join(' - ')
              end
            else
              officer_address << ",#{data_array[0..-1].join(' - ')}"
            end
          end
        end
        agent_info["officer_name"] = officer_name.join("").strip
        agent_info["officer_address"] = officer_address.join("").strip
      end
      agent_info["company_type"] = row[-1].strip
      agent_info
    end

    def file_to_object(publish, base_directory)
      publish.each do |filename, file_location|
        file_name = filename.gsub('.csv', '')
        warn "Unpacking file: #{filename}"
        next unless filename.include? '.csv'
        begin
          csv_data = CSV.parse(File.readlines(file_location).join.scrub)
          total_rows = csv_data.count
          agent_data = {}
          start_index =  0
          while true
            if company_type_row?(csv_data[start_index]) && !agent_data.empty?
              agent_data["company_type"] = csv_data[start_index][0]
              start_index+=1
            else
              agent, start_index = get_agent_info(csv_data, start_index)
              break if agent == []
              agent_data = parse_agent(agent)
            end

            company_data, start_index = get_company_details(csv_data, start_index)
            company_data.each do |company_row|
              data_hash = {}
              data_hash[file_name] = []
              data_row = agent_data.merge(company_row)
              data_hash[file_name] << data_row
              yield(data_hash)
            end
            break if start_index >= total_rows
          end
        rescue CSV::MalformedCSVError
          IO.write("tmp/invalid_#{filename}", file_location, mode: 'a')
        end
      end
    end

    def parse(payload)
      file_to_object(payload['body'], payload['base_directory']) do |entry|
        yield(entry.merge({ 'RetrievedAt' => payload['sampled_at'] }))
      end
    end
  end
end
