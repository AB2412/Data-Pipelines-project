require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'mechanize'
require 'byebug'

module FrCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true

    CREDENTIALS = get_bot_secret("fr")

    def run
      init_db
      init_working_folder
      clean_output_file(output_file_location)
      scan_processing_folder
      fetch_data_results = fetch_data
      fetch_gaps_results = fetch_gaps
      failed_queue_updated = process_failed_company_number
      res = {}
      res.merge!(fetch_data_results) if fetch_data_results.is_a?(Hash)
      res.merge!(fetch_gaps_results) if fetch_gaps_results.is_a?(Hash)
      res.merge!(failed_queue_updated) if failed_queue_updated.is_a?(Hash)
      res
    end

    def init_db
      db_file = "db/frcompaniesfetcher.db"
      @db = SQLite3::Database.new(db_file)
      if File.zero?(db_file)
        command_output = `sqlite3 -separator ',' -batch #{db_file} '.read lib/schema.sql' 2>&1`
      end
    end

    def init_working_folder
      @working_folder = working_data_folder || "#{data_dir}/#{Time.now.strftime('%Y-%m-%d_%H%M')}_processing"
      unless Dir.exist?(@working_folder)
        FileUtils.mkdir_p(@working_folder)
      end
    end

    def scan_processing_folder
      unless Dir.glob("#{@working_folder}/*").blank?
        Dir.glob("#{@working_folder}/*").each do |file_path|
          files = Dir.glob("#{file_path}/*")
          persist({ siren_data: files.select{|e| e.include? "siren"}.first, siret_data: files.select{|e| e.include? "siret"}.first, retrieved_at: Time.now.utc.iso8601 })
        end
      end
    end

    def fetch_data
      $stderr.puts "******* Started fetch_data method ********"
      @added = 0
      res = {}
      @start_date_variable = "start_date"
      @siren_prefix_variable = "fetch_siren_prefix"
      start_date = get_var('start_date') || (Date.today - 5).to_s
      save_var(@start_date_variable, start_date) unless get_var('start_date')
      get_data_via_date_range(start_date, Date.today.to_s)

      res.merge(:added => @added)
    rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
      {:added => @added, fetch_data_output: ex.class.to_s }
    rescue Exception => ex
      {added: @added, :fetch_data_error => {'error' => exception_to_json(ex)}}
    end

    def fetch_gaps
      $stderr.puts "******* Started fetch_gaps method ********"
      @added = 0
      res = {}
      gap_start_date = get_var("gap_start_date") || "2024-03-22"
      save_var("gap_start_date", gap_start_date) unless get_var("gap_start_date")
      end_date = get_var("gap_end_date")
      save_var("gap_end_date", nil) if end_date && (end_date <= gap_start_date)
      gap_end_date = get_var("gap_end_date") || (Date.today - 6).to_s
      save_var("gap_end_date", gap_end_date) unless get_var("gap_end_date")
      @start_date_variable = "gap_end_date"
      @siren_prefix_variable = "gap_siren_prefix"
      get_data_via_date_range(gap_start_date, gap_end_date)
      res.merge(:backfill_added => @added)
    rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
      {:added => @added, fetch_data_output: ex.class.to_s }
    rescue Exception => ex
      {added: @added, :fetch_data_error => {'error' => exception_to_json(ex)}}
    end

    def process_failed_company_number
      count = 0
      $stderr.puts "******* Processing failed queue company records ********"
      unprocessed_company_numbers = sqlite_magic_connection.execute("select company_number from unhandled_response_company_numbers").map{|e| e["company_number"]}
      unprocessed_company_numbers.each do |company_number|
        next if @downloaded_files.include? company_number
        record_url = "https://api.insee.fr/entreprises/sirene/V3.11/siren/#{company_number}"
        siren_data = get_api_response(record_url, company_number)
        next if siren_data.nil?

        json_body = JSON.parse(siren_data.body)
        process_single_record(json_body["uniteLegale"])
        count+=1
      end
      sqlite_magic_connection.execute("delete from unhandled_response_company_numbers where company_number in (#{(['?'] * unprocessed_company_numbers.length).join(', ')})", unprocessed_company_numbers)
      {failed_queue_added: count }
    rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
      {failed_queue_added: count, :update_failed_queue_output => ex.message}
    rescue Exception => ex
      {failed_queue_added: count, :update_failed_queue_error => {'error' => exception_to_json(ex)}}
    end

    def get_json_response(api_url)
      response = get_api_response(api_url)
      return nil if response.nil?
      JSON.parse(response.body)
    end

    def get_data_via_date_range(start_date, end_date)
      start_date = Date.parse(start_date)
      end_date = Date.parse(end_date)
      @starting_time = Time.now.to_i
      dates_array = caller.to_s["fetch_gaps"] ? (start_date..end_date).to_a.reverse : (start_date..end_date).to_a
      dates_array.each do |date|
        $stderr.puts "*********** Processing Date: #{date} ****************"
        fetch_insee_data(date.to_s)
        if (Time.now.to_i - @starting_time > get_constant('FETCHING_RUNTIME_LIMIT').to_i)
          $stderr.puts "************* Timeout Occurred, #{Time.now.to_i - @starting_time} > #{get_constant('FETCHING_RUNTIME_LIMIT').to_i}"
          break
        end
      end
    end

    def get_api_url(date, siren_prefix)
      if siren_prefix
        api_url = "https://api.insee.fr/api-sirene/3.11/siren?q=siren:#{siren_prefix}* AND -periode(categorieJuridiqueUniteLegale:1000) AND statutDiffusionUniteLegale:O AND dateDernierTraitementUniteLegale:[#{date}T00:00:00 TO #{date}T23:59:59]&nombre=#{PER_PAGE_RECORDS}&curseur="
      else
        api_url = "https://api.insee.fr/api-sirene/3.11/siren?q=-periode(categorieJuridiqueUniteLegale:1000) AND statutDiffusionUniteLegale:O AND dateDernierTraitementUniteLegale:[#{date}T00:00:00 TO #{date}T23:59:59]&nombre=#{PER_PAGE_RECORDS}&curseur="
      end
      api_url
    end

    def update_swvariables(date, siren_prefix)
      updated_date = caller.to_s["fetch_gaps"] ? (Date.parse(date)-1).to_s : (Date.parse(date)+1).to_s
      if siren_prefix
        if siren_prefix == "99"
          save_var(@start_date_variable, updated_date)
          save_var(@siren_prefix_variable, nil)
        else
          if siren_prefix.length == 2
            siren_prefix_updated = (siren_prefix.to_i + 1).to_s
            save_var(@siren_prefix_variable, siren_prefix_updated.rjust(2, '0')) #save in swvaraibels
          else
            if siren_prefix.end_with? "9"
              siren_prefix_new = (siren_prefix[0...-1].to_i + 1).to_s
              save_var(@siren_prefix_variable, siren_prefix_new.rjust((siren_prefix.length - 1), '0'))
            else
              siren_prefix_updated = (siren_prefix.to_i + 1).to_s
              save_var(@siren_prefix_variable, siren_prefix_updated.rjust(siren_prefix.length, '0')) #save in swvaraibels
            end
          end
        end
      else
        save_var(@start_date_variable, updated_date)
      end
      [get_var(@start_date_variable), get_var(@siren_prefix_variable)]
    end

    def fetch_insee_data(date)
      page_number = 1
      new_curseur = nil
      siren_prefix = get_var(@siren_prefix_variable)
      @downloaded_files = Dir.glob("#{@working_folder}/*").map{|e| e.split("/").last} rescue []
      loop do
        if (Time.now.to_i - @starting_time > get_constant('FETCHING_RUNTIME_LIMIT').to_i) && (page_number == 1)
          $stderr.puts "************* Timeout Occurred, #{Time.now.to_i - @starting_time} > #{get_constant('FETCHING_RUNTIME_LIMIT').to_i}"
          break
        end
        request_url = get_api_url(date, siren_prefix)
        curseur = (page_number == 1) ? "*" : new_curseur
        api_url = "#{request_url}#{curseur}"
        $stderr.puts "--------- api_url: #{api_url}-----------------------"
        json_body = get_json_response(api_url)
        $stderr.puts "Total Records count is: #{json_body["header"]["total"]}" if json_body
        if json_body.blank?
          page_number = 1
          updated_date, siren_prefix = update_swvariables(date, siren_prefix)
          break if updated_date != date
        elsif (json_body["header"]["total"] <= NARROW_SEARCH_RECORDS_LIMIT)
          process_records(json_body)
          new_curseur = json_body["header"]["curseurSuivant"]
          if (new_curseur.blank?) || (json_body["header"]["nombre"] < PER_PAGE_RECORDS)
            updated_date, siren_prefix = update_swvariables(date, siren_prefix)
            page_number = 1
            break if updated_date != date
          else
            page_number +=1
          end
        else
          page_number = 1
          siren_prefix = siren_prefix ? "#{siren_prefix}0" : "00"
        end
      end
    end

    def process_single_record(data_hash)
      return nil if data_hash.nil?
      siren_number = data_hash["siren"]
      $stderr.puts "**************************************************************"
      $stderr.puts "SIREN: #{siren_number}"
      if @downloaded_files.include? siren_number
        $stderr.puts "The record with Siren: #{siren_number} already exists"
        return nil
      end
      entity_details = data_hash["periodesUniteLegale"].first
      nic_unite_legale = entity_details["nicSiegeUniteLegale"]
      return nil if nic_unite_legale.blank?
        
      siret_number = siren_number + nic_unite_legale
      $stderr.puts "SIRET: #{siret_number}"
      siret_api = "https://api.insee.fr/api-sirene/3.11/siret/#{siret_number}"
      response = get_api_response(siret_api, siren_number)
      return nil if response.nil?
      data_hash = { siren_data: store_raw_html(siren_number, "siren", data_hash.to_json), siret_data: store_raw_html(siren_number, "siret", response.body), retrieved_at: Time.now.utc.iso8601 }
      return nil if data_hash[:siren_data].blank? || data_hash[:siret_data].blank?
      persist(data_hash)
      data_hash
    end

    def process_records(json_body)
      processing_data = json_body["unitesLegales"]
      processing_data.each do |data_hash|
        if process_single_record(data_hash)
          @added +=1
        end
      end
    end

    def get_api_response(api_url, siren_number = nil)
      log_info = proc do |exception, try, elapsed_time, next_interval|
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end
      
      tries = 5
      Retriable.retriable tries: tries, base_interval: 10, on_retry: log_info do |try|
        return nil if try == tries
        api_response = browser.get(api_url, nil, nil, headers)
        sleep(0.5)
        api_response
      rescue Mechanize::ResponseCodeError => ex
        if ex.response_code == '404'
          $stderr.puts 'No items found for this query'
          return nil
        elsif ['500', '503', '504', '403'].include?(ex.response_code)
          $stderr.puts 'Could not process request for the identifier: ' + api_url.split("/").last
          sqlite_magic_connection.execute("insert or ignore into unhandled_response_company_numbers(company_number, error_details) values(?,?)", [siren_number, ex.message]) if siren_number
          return nil
        else
          raise ex
        end
      end
    end

    def browser
      if @browser.nil?
        @browser ||= Mechanize.new do |b|
          b.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:28.0) Gecko/20100101 Firefox/28.0'
          b.max_history = 1
          b.open_timeout = 120
          b.read_timeout = 120
          b.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end
      @browser
    end

    def headers
      {
        "Accept" => "application/json",
        "X-INSEE-Api-Key-Integration" => CREDENTIALS['API_KEY']
      }
    end

    def exception_to_json(ex)
      {'klass' => ex.class.to_s, 'message' => ex.message, 'backtrace' => ex.backtrace}
    end

    def store_raw_html(siren_number, file_name, page_data)
      begin
        file = File.join(@working_folder, siren_number)
        page_response = (JSON.parse(page_data).keys.include? "etablissement") ? JSON.parse(page_data)["etablissement"].to_json : page_data
        unless (File.directory?(file)) && (Dir.glob(File.join(file, "*")).count == 2)
          file_path = File.join(FileUtils.mkdir_p(file), "#{file_name}.json")
          IO.write(file_path, page_response)
          file_path
        else
          nil
        end
      rescue Exception => ex
        $stderr.puts "store_raw_html exception: #{ex.message}"
        sqlite_magic_connection.execute("insert or ignore into unhandled_response_company_numbers(company_number, error_details) values(?,?)", [siren_number, ex.message])
        nil
      end
    end
  end
end
