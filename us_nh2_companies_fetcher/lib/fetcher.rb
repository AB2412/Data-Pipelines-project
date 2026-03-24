require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'mechanize'

module UsNh2CompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true

    # CREDENTIALS = get_bot_secret("us_nh2")
    # WEBSHARE_CREDENTIALS = get_bot_secret(nil, "webshare")

    def folders
      @paths = []
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                    single_factor_authentication
                    zip_file_download
                   end
      @folders
    end

    def webshare_browser
      if @webshare_browser.nil?
        @webshare_browser = Mechanize.new
        # @webshare_browser.set_proxy(WEBSHARE_CREDENTIALS["OC_PROXY"], WEBSHARE_CREDENTIALS["OC_PROXY_PORT"], WEBSHARE_CREDENTIALS["OC_PROXY_USERNAME"], WEBSHARE_CREDENTIALS["OC_PROXY_PASSWORD"])
        @webshare_browser.set_proxy("23.95.150.145", "6114", "mmrqbgcn","s4hfbwlfibq3")
        @webshare_browser.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      @webshare_browser
    end

    def zyte_browser
      if @zyte_browser.nil?
        @zyte_browser = Mechanize.new
        # @zyte_browser.set_proxy CREDENTIALS["ZYTE_API"]["HOST"], CREDENTIALS["ZYTE_API"]["PORT"], CREDENTIALS["ZYTE_API"]["KEY"], ''
        @zyte_browser.set_proxy("api.zyte.com", "8011", "996e0d4781164f11988c3f1106f649db","")
        @zyte_browser.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      @zyte_browser
    end

    def request_with_retries(browser, url, headers, params={}, request_type='get')
      log_info = Proc.new do |exception, try, elapsed_time, next_interval|
        $stderr.puts "Processing failed - #{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      Retriable.retriable tries: 5, base_interval: 100, on_retry: log_info do
        warn "******** Request hitting for: #{url} *********"
        if request_type == 'get'
          response = browser.get(url, nil, nil, headers)
        elsif request_type == 'post'
          browser.post(url, params, headers)
        end
      end
    end

    def get_verification_token
      main_page = request_with_retries(zyte_browser, "https://quickstart.sos.nh.gov/online", HEADER)
      main_page_body = Nokogiri::HTML(main_page.body)
      token = main_page.form["__RequestVerificationToken"]
      raise OpencBot::SourceClosedForMaintenance.new('Unable to get the website token!') if token.blank?
      [token, main_page_body]
    end

    def get_headers(referer, cookie)
      headers = HEADER.dup
      unless cookie.nil?
        headers['Referer'] = referer
        headers["Cookie"] = cookie
      else
        headers['Referer'] = referer
      end
      headers
    end

    def otp_verification
      cookie_headers = get_cookie_headers(webshare_browser)
      header = get_headers('https://quickstart.sos.nh.gov/online/Account/SingleFactorAuthentication', nil)
      page = request_with_retries(webshare_browser, "#{HOST}/online/Account/OTPVerification", cookie_headers, {"LoginType" => "Email"}, 'post')
      warn "OTPVerification request: #{page.code}"
      page
    end

    def get_cookie_headers(browser_type)
      cookies = browser_type.cookie_jar.cookies
      cookie_headers = HEADER
      cookie_headers["Cookie"] = "#{cookies.last.to_s}\;#{cookies.first.to_s}\;cookie_consent=accepted"
      cookie_headers
    end

    def auth_header(token)
      {
        "__RequestVerificationToken" => token,
        "hdnDebtorSearched" => "",
        "hdnError" => "",
        "hdnErrorMsg" => "",
        "hdnRedirection" => "",
        "hdnSelectedStatus" => "",
        "hdnUccSerch" => "",
        "hdnWrongEntries" => "",
        "hdnddlTimeFrame" => "",
        "hdnsearchCriteria" => "",
        "txtUsername" => "areeba"#CREDENTIALS["REGISTRY_LOGIN_USERNAME"]
      }
    end

    def verify_authenticate_code(code)
      headers = get_headers('https://quickstart.sos.nh.gov/online/Account/OTPVerification', nil)
      request_params = {
        "hdnError" => "",
        "txtDig1" => "#{code[0]}",
        "txtDig2" => "#{code[1]}",
        "txtDig3" => "#{code[2]}",
        "txtDig4" => "#{code[3]}",
        "txtDig5" => "#{code[4]}",
        "txtDig6" => "#{code[5]}",
      }.to_query

      page = request_with_retries(webshare_browser, "#{HOST}/online/Account/VerifyAuthenticateCode", headers, request_params, 'post')
      warn "Verify Authentication request: #{page.code}"
      raise "No new code fetched" if page.body.exclude? "areeba"#CREDENTIALS["REGISTRY_LOGIN_USERNAME"]
      page
    end

    def single_factor_authentication
      token, page = get_verification_token
      cookie_headers = get_cookie_headers(zyte_browser)
      auth_page = request_with_retries(webshare_browser, "#{HOST}/online/Account/SingleFactorAuthentication", cookie_headers, auth_header(token).to_query, 'post')
      warn "SingleFactorAuthentication request: #{auth_page.code}"
      sleep(2)
      verified_page = otp_verification
      sleep(10)
      code = email_reader("areeba@agilekode.com", "wcma rjtf dshr epds")#(CREDENTIALS["GMAIL"]["GMAIL_ACC_EMAIL"], CREDENTIALS["GMAIL"]["GMAIL_ACC_PASSWORD"])
      verify_authenticate_code(code)
    end

    def get_file_date_and_name(tr)
      file_date = Date.strptime((tr.css("td")[3].text), "%m/%d/%Y").strftime("%Y-%m-%d")
      file_name = tr.css("a").map{|o| o["onclick"]}.map{|f| f.match(/['"](.+?)['"]/)}[0][1].gsub("\\\\",'\\')
      [file_date, file_name]
    end

    def delete_file_path(file_path)
      FileUtils.rm_rf(file_path) if file_path && Dir.exist?(file_path)
    end

    def zip_file_download
      $stderr.puts "DOWNLOADING ZIP FILES"
      download_page = request_with_retries(webshare_browser, "https://quickstart.sos.nh.gov/online/CorporationDataSales/CorpDataSalesDashboard", HEADER)
      file_names = download_page.css("tbody tr").map{|e| get_file_date_and_name(e)}
      file_path = nil
      file_names.sort_by { |entry| Date.parse(entry[0]) }.each do |file_date, payload_file_name|
        file_path = (payload_file_name.downcase.include? "weekly") ? "data/weekly/#{file_date}" : "data/bulk/#{file_date}"
        FileUtils.mkdir_p(file_path) unless Dir.exist? (file_path)

        if Dir.glob("#{file_path}/*.csv").empty?
          download_headers = HEADER.merge({
            "zyte-file-download" => "true",
            "X-Zyte-HttpResponseBody" => "1"
          })
          zip_file_res = request_with_retries(zyte_browser, "https://quickstart.sos.nh.gov/online/CorporationDataSales/DownloadCorporationDataSales", download_headers, {"hdnDataSalesFilename" => payload_file_name}.to_query, 'post')
          file_name = zip_file_res.filename
          zip_file_res.save("#{file_path}/#{file_name}")
          unzip_output = `unzip #{file_path}/#{file_name} -d #{file_path}`
          raise "Failed to unzip the file: \n#{unzip_output}" unless $CHILD_STATUS.success?
          @paths << file_path
        end
      end
      @paths
    rescue Exception => e
      @paths.each { |path| delete_file_path(path)}
      delete_file_path(file_path)
      raise e.message
    end

    def fetch_data_via_dataset(_options = {})
      if folders.blank?
        warn 'Either the data folder is not set, or there are no files to process in the data folder.' 
        return nil
      end

      folders.each do |folder|
        sampled_at = Time.parse(folder.split('/').last + ' UTC').iso8601
        entries = {}
        Dir.glob("#{folder}/*.csv") do |filename|
          warn filename
          entries[File.basename(filename)] = filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries,
                  'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
