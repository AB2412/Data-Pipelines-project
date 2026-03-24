require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'

require 'mechanize'

module UsOkCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true

    CREDENTIALS = get_bot_secret("us_ok")
    WEBSHARE_CREDENTIALS = get_bot_secret(nil, "webshare")
    CAPTCHA_CREDENTIALS = get_bot_secret(nil, "2captcha")

    def run
      res = {}
      options = {}
      init_db
      init_working_folder
      clean_output_file(output_file_location)
      scan_processing_folder
      login_request
      fetch_data_results = fetch_data
      res.merge!(fetch_data_results) if fetch_data_results.is_a?(Hash)
      if res.has_key?( :fetch_data_error )
        raise "\n" + JSON.pretty_generate(res)
      end
      res
    rescue Exception => e
      raise e
    end

    def scan_processing_folder
      unless Dir.glob("#{@working_folder}/*").blank?
        Dir.glob("#{@working_folder}/*").each do |file_path|
          persist({"#{file_path.split("/").last.gsub(".html",'')}": file_path, retrieved_at: Time.now.utc.iso8601 })
        end
      end
    end

    def init_working_folder
      @working_folder = working_data_folder || "#{data_dir}/#{Time.now.strftime('%Y-%m-%d_%H%M')}_processing"
      unless Dir.exist?(@working_folder)
        FileUtils.mkdir_p(@working_folder)
      end
    end

    def init_db
      db_file = "db/usokcompaniesfetcher.db"
      @db = SQLite3::Database.new(db_file)
      if File.zero?(db_file)
        command_output = `sqlite3 -separator ',' -batch #{db_file} '.read lib/schema.sql' 2>&1`
      end
    end

    def headers(referer_url="https://www.sos.ok.gov/sosSecurity/Default.aspx")
      {
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Accept-Language" => "en-US,en;q=0.9",
        "Cache-Control" => "max-age=0",
        "Connection" => "keep-alive",
        "Referer" => referer_url
      }
    end

    def browser
      if @browser.nil?
        @browser ||= Mechanize.new do |b|
          b.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:28.0) Gecko/20100101 Firefox/28.0'
          b.max_history = 1
          b.open_timeout = 120
          b.read_timeout = 120
          b.verify_mode = OpenSSL::SSL::VERIFY_NONE
          b.set_proxy(WEBSHARE_CREDENTIALS["OC_PROXY"], WEBSHARE_CREDENTIALS["OC_PROXY_PORT"], WEBSHARE_CREDENTIALS["OC_PROXY_USERNAME"], WEBSHARE_CREDENTIALS["OC_PROXY_PASSWORD"])
        end
      end
      @browser
    end

    def get_cloudflare_site_key(response)
      raw =  response.css('script')[-4].text
      index_no = raw.index('turnstile.render(')
      raw = raw[index_no .. -1]
      index_no = raw.index("sitekey: '")
      raw = raw[index_no+10 .. -1]
      index = raw.index("'")
      site_key = raw[0...index]
      site_key
    end

    def solve_cloudflare(site_key)
      api_key = CAPTCHA_CREDENTIALS["CAPTCHA_API_KEY"]
      target_url = 'https://www.sos.ok.gov/sosSecurity/Default.aspx'
      params = {
        key: api_key,
        method: "turnstile",
        sitekey: site_key,
        pageurl: target_url,
        json: 1
      }
      response = get_page_response("http://2captcha.com/in.php", {}, params)
      result = JSON.parse(response.body)
      if result["status"] == 1
        request_id = result["request"]
        $stderr.puts "CAPTCHA submitted successfully, request ID: #{request_id}"

        sleep 30
        solved_captcha = nil
        check_response = get_page_response("http://2captcha.com/res.php?key=#{api_key}&action=get&id=#{request_id}&json=1")
        sleep(10)
        check_result = JSON.parse(check_response.body)
        if check_result["status"] == 1
          solved_captcha = check_result["request"]
          $stderr.puts "Solved CAPTCHA Token: #{solved_captcha}"
          return solved_captcha
        end
      end
    end

    def get_page_response(url, headers= nil, params = nil)
      log_info = proc do |exception, try, elapsed_time, next_interval|
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      Retriable.retriable tries: 5, base_interval: 10, on_retry: log_info do |try|
        if params
          api_response = browser.post(url, params, headers)
        else
          api_response = browser.get(url, nil, nil, headers)
        end
      end
    end

    def get_login_params(response, cloudflare_response)
      view_state = response.css("input#__VIEWSTATE").first["value"]
      view_state_generator = response.css("input#__VIEWSTATEGENERATOR").first["value"]
      event_target = response.css("input#__EVENTTARGET").first["value"]
      event_argument = response.css("input#__EVENTARGUMENT").first["value"]
      login_params = {
        "__EVENTARGUMENT" => event_argument,
        "__EVENTTARGET" => event_target,
        "__VIEWSTATE" => view_state,
        "__VIEWSTATEGENERATOR" => view_state_generator,
        "ctl00$DefaultContent$LoginCtrl1$lvLoginView$logLogin$LoginButton" => "Sign In",
        "ctl00$DefaultContent$LoginCtrl1$lvLoginView$logLogin$Password" => CREDENTIALS["PORTAL_PASSWORD"],
        "ctl00$DefaultContent$LoginCtrl1$lvLoginView$logLogin$UserName" => CREDENTIALS["PORTAL_USERNAME"],
        "cf-turnstile-response" => cloudflare_response,
        "foo" => cloudflare_response
      }
      login_params
    end

    def login_request
      response = get_page_response("https://www.sos.ok.gov/sosSecurity/Default.aspx")
      cloudflare_site_key = get_cloudflare_site_key(response)
      solved_cloudflare_response = nil
      5.times.each do |captca_solver_try|
        solved_cloudflare_response = solve_cloudflare(cloudflare_site_key)
        $stderr.puts "solved_cloudflare_response: #{solved_cloudflare_response}"
        break unless solved_cloudflare_response.blank?
      end
      raise "Unable to solve the Cloudflare" if solved_cloudflare_response.blank?
      login_params = get_login_params(response, solved_cloudflare_response)
      login_response = get_page_response("https://www.sos.ok.gov/sosSecurity/Default.aspx", headers, login_params)
    end

    def update_datum(company_number, options = {})
      return unless raw_data = fetch_datum(company_number, options)
      html_file = store_raw_html(raw_data)
      persist({"#{raw_data[:entity_id]}": html_file, retrieved_at: Time.now.utc.iso8601 }) if html_file
      raw_data
    end

    def store_raw_html(raw_data)
      unless Dir.glob("#{@working_folder}/*.html").include? "#{@working_folder}/#{raw_data[:entity_id]}.html"
        file_path = File.join(FileUtils.mkdir_p(@working_folder), "#{raw_data[:entity_id]}.html")
        IO.write(file_path, raw_data[:company_page])
        file_path
      else
        nil
      end
    end

    def fetch_data
      warn "========IN THE FETCH DATA========"
      original_count = record_count
      res = {}
      if use_alpha_search
        fetch_data_via_alpha_search
        res[:run_type] = 'alpha'
      else
        new_highest_numbers = fetch_data_via_incremental_search
        res[:run_type] = 'incremental'
        res[:output] = "New highest numbers = #{new_highest_numbers.inspect}"
      end
      records_added = record_count - original_count
      res.merge(:added => records_added)
    rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
      {:added => (record_count - original_count), run_type: 'alpha/incremental', fetch_data_output: ex.class.to_s }
    rescue Exception => ex
      { added: (record_count - original_count), run_type: 'alpha/incremental', :fetch_data_error => {'error' => exception_to_json(ex)}}
    end

    def exception_to_json(ex)
      {'klass' => ex.class.to_s, 'message' => ex.message, 'backtrace' => ex.backtrace}
    end

    def incremental_search(uid, options={})
      first_number = uid.dup
      current_number = nil
      error_count = 0
      last_good_co_no = nil
      skip_existing_entries = options.delete(:skip_existing_entries)
      uid = increment_number(uid, options[:offset]) if options[:offset]
      loop do
        current_number = uid
        if datum_exists?(uid)
          uid = increment_number(uid)
          error_count = 0
          next
        elsif update_datum(current_number, false)
          last_good_co_no = current_number
          error_count = 0
          save_var(:highest_entry_uids, [ last_good_co_no ])
        else
          error_count += 1
          $stderr.puts "Failed to find company with uid #{current_number}. Error count: #{error_count}" if verbose?
          break if error_count > max_failed_count
        end
        uid = increment_number(uid)
      end
      last_good_co_no ? last_good_co_no.to_s : first_number
    end

    def fetch_datum(company_number, options = {} )
      $stderr.puts( "Processing: #{ company_number }" )
      raise OpencBot::OutOfPermittedHours.new("Request at #{ Time.now.utc.iso8601 } is not out business hours (#{allowed_hours})") if in_prohibited_time? && caller.to_s['update_data']
      sleep_before_http_req
      response = get_page_response("https://www.sos.ok.gov/corp/corpInformation.aspx?id=#{company_number}")
      raise "CloudFlare request" if response.body.include? "Please enter your name"
      return nil if response.css("dd").text.include? "Record not found"
      { company_page: response.body.force_encoding( 'utf-8' ) ,entity_id: company_number }
    rescue SocketError, Net::HTTP::Persistent::Error, Net::HTTPFatalError
      $stderr.puts 'Could not process request for the identifier: ' + company_number
      return nil
    rescue Mechanize::ResponseCodeError => ex
      if ['500', '503', '504'].include?(ex.response_code)
        $stderr.puts 'Could not process request for the identifier: ' + company_number
        return nil
      else
        raise ex
      end
    end
  end
end
