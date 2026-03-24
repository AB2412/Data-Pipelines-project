require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'mechanize'

module Fr2CompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true

    CREDENTIALS = get_bot_secret("fr2")

    def run
      res = {}
      init_db
      init_working_folder
      clean_output_file(output_file_location)
      scan_processing_folder
      load_ape_code_data
      fetch_token
      fetch_data_results = fetch_data
      fetch_gaps_results = fetch_gaps
      res.merge!(fetch_data_results) if fetch_data_results.is_a?(Hash)
      res.merge!(fetch_gaps_results) if fetch_gaps_results.is_a?(Hash)
      res
    end

    def fetch_data
      @added = 0
      $stderr.puts "***********IN THE FETCH DATA*****************"
      res = {}
      @page_num = "fetch_data_page_num"
      @pagination_company_number = "search_after_company_number"
      @start_date_variable = "start_date"
      start_date = get_var('start_date') || (Date.today - 10).to_s
      save_var("start_date", start_date) unless get_var("start_date")
      get_data_via_date_range(start_date, Date.today.to_s)
      res.merge(:added => @added)
    rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
      {:added => @added, fetch_data_output: ex.class.to_s }
    rescue Exception => ex
      {added: @added, :fetch_data_error => {'error' => exception_to_json(ex)}}
    end

    def fetch_gaps
      @added = 0
      res = {}
      $stderr.puts "*******************FETCH GAPS*************************"
      gap_start_date = get_var("gap_start_date") || "2022-12-22"
      save_var("gap_start_date", gap_start_date) unless get_var("gap_start_date")
      gap_end_date = get_var("gap_end_date") || (Date.today - 11).to_s
      save_var("gap_end_date", gap_end_date) unless get_var("gap_end_date")
      @start_date_variable = "gap_end_date"
      @page_num = "fetch_gaps_page_num"
      @pagination_company_number = "gaps_search_after_company_number"

      get_data_via_date_range(gap_start_date, gap_end_date)
      res.merge(:backfill_added => @added)
    rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
      {:added => @added, fetch_data_output: ex.class.to_s }
    rescue Exception => ex
      {added: @added, :fetch_data_error => {'error' => exception_to_json(ex)}}
    end

    def get_data_via_date_range(start_date, end_date)
      start_date = Date.parse(start_date)
      end_date = Date.parse(end_date)
      @starting_time = Time.now.to_i
      dates_array = caller.to_s["fetch_gaps"] ? (start_date..end_date).to_a.each_cons(2).to_a.reverse : (start_date..end_date).to_a.each_cons(2).to_a
      dates_array.each do |date_chunk|
        $stderr.puts "*********** Processing Date: #{date_chunk} ****************"
        inpi_api_result(date_chunk.first.to_s, date_chunk.last.to_s)
        break if timeout? || @api_response_code == "429"
      end
    end

    def get_date_interval_count(start_date, end_date)
      record_count_url = "https://registre-national-entreprises.inpi.fr/api/companies/diff/count?from=#{start_date}&to=#{end_date}"
      api_response = get_api_response(record_count_url)
      $stderr.puts "------------------ Search Total count is: #{api_response.body} --------------"
    end

    def get_current_page(api_response_code)
      api_response_code && api_response_code == "200" ? PAGE_SIZE_ARRAY.sample : (1..20).to_a.sample
    end

    def inpi_api_result(start_date, end_date)
      @already_downloaded_files = Dir.glob("#{working_data_folder}/*").map{|e| e.split("/").last} rescue []
      page_number = get_var(@page_num) ? get_var(@page_num).to_i : 1
      pagination_company_number = get_var(@pagination_company_number) || ""
      get_date_interval_count(start_date, end_date)
      @api_response_code = nil

      loop do
        if timeout?
          $stderr.puts "************* Timeout occurred *****************"
          save_variables(pagination_company_number,  page_number.to_s, false)
          break
        end

        file_name = "#{start_date}-to-#{end_date}_page_#{page_number}"
        if @already_downloaded_files.include? "#{file_name}.json"
          $stderr.puts "ALREADY EXISTS --> #{file_name}"
          page_number += 1
          next
        end
        @current_page_size = get_current_page(@api_response_code)
        pagination_search_after = (page_number == 1) ? "pagination-search-after" : pagination_company_number
        inpi_api_url = "https://registre-national-entreprises.inpi.fr/api/companies/diff?from=#{start_date}&to=#{end_date}&pageSize=#{@current_page_size}&searchAfter=#{pagination_search_after}"
        $stderr.puts "Processing URL: #{inpi_api_url}"
        $stderr.puts "Page Number: #{page_number}"
        api_response = get_api_response(inpi_api_url)
        sleep(1)
        @api_response_code = api_response.code
        $stderr.puts "******* api_response_code: #{@api_response_code} *********"

        if @api_response_code == "429"
          save_variables(pagination_company_number, page_number.to_s, false)
          break
        end

        next if @api_response_code != "200"
        pagination_company_number, api_response = api_response.header["pagination-search-after"], api_response.body
        persist({"#{file_name}": store_raw_html(api_response, file_name), retrieved_at: Time.now.utc.iso8601}) unless ((api_response.blank?) || (api_response == "[]"))
        if (api_response.blank?) || (api_response == "[]") || last_page?(api_response)
          save_variables(start_date, end_date)
          break
        end
        page_number += 1
        @added += 1
      end
    rescue Exception => ex
      save_variables(pagination_company_number, page_number.to_s, false)
      raise ex
    end

    def save_variables(swvariable1, swvariable2, complete_search = true)
      if complete_search
        updated_date = (caller.to_s["fetch_gaps"]) ? swvariable1 : swvariable2
        save_var(@start_date_variable, updated_date)
        save_var(@pagination_company_number, nil)
        save_var(@page_num, nil)
      else
        save_var(@pagination_company_number, swvariable1)
        save_var(@page_num, swvariable2)
      end
    end

    def last_page?(api_response)
      records_count = JSON.parse(api_response).map{|e| e["company"]["siren"]}.count
      $stderr.puts "-------- API Response Records count is: #{records_count} --------------"
      records_count < @current_page_size
    end

    def timeout?
      Time.now.to_i - @starting_time > get_constant('FETCHING_RUNTIME_LIMIT').to_i
    end

    def load_ape_code_data
      if Dir.glob("lib/mapping_files/*").exclude? "lib/mapping_files/CODE_APE.json"
        code_ape_response = browser.get("https://www.startbusinessinfrance.com/code-ape")
        rows = code_ape_response.at_css('.table-responsive').css('tr')
        key_value_pairs = []
        html_tag_pattern = /<font.*?>|<\/font>/i
        rows[1..].each do |row|
          values = row.css('td').map{|e| e.text.squish}[0..1]
          next if values.first.include? "SECTION"

          data_hash = {
            "Code" => values[0].gsub(html_tag_pattern, '').squish,
            "Description" => values[1]
          }
          key_value_pairs << data_hash unless data_hash["Code"].blank?
        end
        File.write('lib/mapping_files/CODE_APE.json', JSON.pretty_generate(key_value_pairs))
      end
    end

    def headers
      {
        "Authorization" => "Bearer #{@token}"
      }
    end

    def get_api_response(inpi_api_url)
      log_info = proc do |exception, try, elapsed_time, next_interval|
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      tries = 5
      Retriable.retriable tries: tries, base_interval: 10, on_retry: log_info do |try|
        api_response = browser.get(inpi_api_url, nil, nil, headers)
      rescue Mechanize::ResponseCodeError => ex
        api_response = ex.page
        if api_response.code == '401'
          $stderr.puts ex
          @browser = nil
          fetch_token
          api_response
        elsif api_response.code == "500" || api_response.code == "429"
          $stderr.puts ex
          api_response
        else
          raise ex
        end
      end
    end

    def fetch_token
      response = browser.post("https://registre-national-entreprises.inpi.fr/api/sso/login", {"username" => CREDENTIALS["USERNAME"], "password" => CREDENTIALS["PASSWORD"]}.to_json, {'Content-Type' => "application/json"})
      @token = JSON.parse(response.body)["token"]
      $stderr.puts "*********** Token is renewed: #{@token} *****************"
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

    def exception_to_json(ex)
      {'klass' => ex.class.to_s, 'message' => ex.message, 'backtrace' => ex.backtrace}
    end

    def init_db
      db_file = "db/fr2companiesfetcher.db"
      @db = SQLite3::Database.new(db_file)
      if File.zero?(db_file)
        command_output = `sqlite3 -separator ',' -batch #{db_file} '.read lib/schema.sql' 2>&1`
      end
    end

    def init_working_folder
      @working_folder = working_data_folder || "#{data_dir}/#{Time.now.strftime('%Y-%m-%d_%H%M')}_processing"
      clean_output_file(output_file_location)
      unless Dir.exist?(@working_folder)
        FileUtils.mkdir_p(@working_folder)
      end
    end

    def scan_processing_folder
      unless Dir.glob("#{@working_folder}/*").blank?
        Dir.glob("#{@working_folder}/*").each do |file_path|
          persist({"#{file_path.split("/").last.gsub(".json","")}": file_path, retrieved_at: Time.now.utc.iso8601})
        end
      end
    end

    def store_raw_html(api_response, file_name)
      unless File.exist?("#{@working_folder}/#{file_name}.json")
        file_path = File.join(FileUtils.mkdir_p(@working_folder), "#{file_name}.json")
        IO.write(file_path, JSON.parse(api_response).to_json)
        file_path
      else
        nil
      end
    end
  end
end
