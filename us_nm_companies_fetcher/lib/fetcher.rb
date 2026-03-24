require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'mechanize'
require 'retriable'

module UsNmCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function
    USE_ALPHA_SEARCH = false
    WEBSHARE_CREDENTIALS = get_bot_secret(nil, "webshare")

    def run
      init_db
      init_browser
      process_registry_queue
      fetch_data_results = fetch_data
      res = {}
      res.merge!(fetch_data_results) if fetch_data_results.is_a?(Hash)
      res
    end

    def init_browser
      puts "Initializing browser..."
      @agent = Mechanize.new
      @agent.set_proxy(WEBSHARE_CREDENTIALS["OC_PROXY"], WEBSHARE_CREDENTIALS["OC_PROXY_PORT"], WEBSHARE_CREDENTIALS["OC_PROXY_USERNAME"], WEBSHARE_CREDENTIALS["OC_PROXY_PASSWORD"])
      @agent.user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
      @agent.request_headers = {
        'Accept' => 'application/json, text/plain, */*',
        'Accept-Language' => 'en-US,en;q=0.9',
        'Connection' => 'keep-alive'
      }
    end

    def init_db
      db_file = "db/usnmcompaniesfetcher.db"
      @db = SQLite3::Database.new(db_file)
      if File.zero?(db_file)
        command_output = `sqlite3 -separator ',' -batch #{db_file} '.read lib/schema.sql' 2>&1`
      end
      highest_entry_uids = get_var('highest_entry_uids')
      if highest_entry_uids.nil?
        save_var('highest_entry_uids', ['0000001'])
      end
    end

    def process_registry_queue
      warn "*** Fetching Process Registry Queue ***"
      missing_company_numbers = @db.execute("Select company_number from registry_queue").flatten
      return if missing_company_numbers.blank?
      missing_company_numbers.each do |company_number|
        warn "*** Fetching Process Registry Queue company number: #{company_number} ***"
        if update_datum(company_number)
          @db.execute("delete from registry_queue where company_number = ?" , company_number)
        end
      end
    end

    def update_datum(company_number, options = {})
      return unless raw_data = fetch_datum(company_number, options)
      persist(raw_data) unless raw_data.blank?
      raw_data
    end

    def incremental_search(uid, options = {})
      first_number = uid.dup
      current_number = nil
      error_count = 0
      last_good_co_no = nil
      skip_existing_entries = options.delete(:skip_existing_entries)
      uid = increment_number(uid, options[:offset]) if options[:offset]
      started_at = Time.now.utc
      loop do
        break if Time.now.utc - started_at > FETCH_DATA_RUNTIME_LIMIT
        current_number = uid
        if skip_existing_entries && datum_exists?(uid)
          uid = increment_number(uid)
          error_count = 0
          next
        elsif update_datum(current_number, false)
          last_good_co_no = current_number
          error_count = 0
        else
          error_count += 1
          puts "Failed to find company with uid #{current_number}. Error count: #{error_count}" if verbose?
          break if error_count > max_failed_count
        end
        uid = increment_number(uid)
      end
      last_good_co_no ? last_good_co_no.to_s : first_number
    end

    def fetch_datum(company_number, options = {})
      sleep 20
      warn "Fetching data for company number: #{company_number}"

      url = SOURCE_URL
      params = {
        'SEARCH_VALUE' => company_number,
        'QueryTypeId' => '2',
        'BusinessRecordTypeId' => '0',
        'BusinessStatusTypeId' => '0'
      }

      response = nil
      log_info = proc do |exception, try, elapsed_time, next_interval|
        init_browser
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      Retriable.retriable tries: 5, base_interval: 120, on_retry: log_info do
        response = @agent.get(url, params)
      end

      if response.code == '200'
        return nil if JSON.parse(response.body)['rows'].empty?
        JSON.parse(response.body)['rows']
      else
        raise "Failed to fetch data: #{response.code} #{response.body}"
      end
    rescue Mechanize::ResponseCodeError, Net::HTTPError, Net::HTTPFatalError, Timeout::Error => e
      $stderr.puts "Error fetching data for company number #{company_number}: #{e.message}"
      nil
    end
  end
end
