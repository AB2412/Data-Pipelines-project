require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'mechanize'

module UsOk2CompaniesFetcher
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

    def folders
      @paths = []
      @folders ||= if ENV['DATA_FOLDER']
                     [file: ENV['DATA_FOLDER'], transaction_date: Time.now.utc.iso8601]
                   else
                    scrape_files_from_portal
                   end
      @folders
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

    def headers(referer_url="https://www.sos.ok.gov/sosSecurity/Default.aspx")
      {
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Accept-Language" => "en-US,en;q=0.9",
        "Cache-Control" => "max-age=0",
        "Connection" => "keep-alive",
        "Host" => "www.sos.ok.gov",
        "Origin" => "https://www.sos.ok.gov",
        "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Referer" => referer_url
      }
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

    def initialize_main_db
      db_file = "db/usok2companiesfetcher.db"
      @db = SQLite3::Database.new(db_file, results_as_hash: true)
      command_output = Open3.capture3("sqlite3 -batch #{db_file} '.read lib/schema.sql'") if File.zero?(db_file)
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
        sleep 30
        check_result = JSON.parse(check_response.body)
        if check_result["status"] == 1
          solved_captcha = check_result["request"]
          $stderr.puts "Solved CAPTCHA Token: #{solved_captcha}"
          return solved_captcha
        end
      end
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

    def scrape_files_from_portal
      response = get_page_response("https://www.sos.ok.gov/sosSecurity/Default.aspx")
      cloudflare_site_key =  get_cloudflare_site_key(response)
      solved_cloudflare_response = nil
      5.times.each do |captca_solver_try|
        solved_cloudflare_response = solve_cloudflare(cloudflare_site_key)
        $stderr.puts "solved_cloudflare_response: #{solved_cloudflare_response}"
        break unless solved_cloudflare_response.blank?
      end
      raise "Unable to solve the Cloudflare" if solved_cloudflare_response.blank?
      login_params = get_login_params(response, solved_cloudflare_response)
      login_response = get_page_response("https://www.sos.ok.gov/sosSecurity/Default.aspx", headers, login_params)
      history_page_response = get_page_response("https://www.sos.ok.gov/client/history.aspx")
      record_urls = history_page_response.css("div.AspNet-GridView tbody tr td a").map{|s| "https://www.sos.ok.gov/client/#{s['href']}"}
      record_urls.each do |url|
        $stderr.puts "*********** Processing: #{url} ************"
        response = get_page_response(url)
        transaction_date = response.css("li.AspNet-DetailsView-Alternate").select{|s| s.css("span.AspNet-DetailsView-Name").text.strip == "DATE:"}.first.css("span.AspNet-DetailsView-Value").text
        transaction_date = DateTime.strptime(transaction_date, "%m/%d/%Y %I:%M:%S").iso8601
        file_page_urls = response.css("div.AspNet-GridView table tr td a").map{|s| parsed_url(s['href'])}
        file_page_urls.each do |file_page_url|
          next unless file_page_url.include?("bulkorder")
          $stderr.puts "*********** Processing Document: #{file_page_url} ************"
          download_file(file_page_url, url, transaction_date)
        end
      end
      @paths.sort_by{|hash| hash[:file]}
    end

    def download_file(file_page_url, reference_url, transaction_date)
      download_page = get_page_response(file_page_url, headers(reference_url))
      file_links = download_page.css("td a").select{|e| e.text.include? "CORP"}.map{|s| parsed_url(s["href"])}
      file_links.each do |file_link|
        file_path, zip_file_name = '', ''
        begin
          $stderr.puts "********** File Link: #{file_link} ********************"
          folder_name = Date.strptime(file_link.split("/").last.gsub(".ZIP", '').split("_").last, "%y%m%d")
          $stderr.puts "FOLDER: #{folder_name}"
          zip_file_name = file_link.split("/").last
          file_path = "data/#{folder_name}"
          FileUtils.mkdir(file_path) unless Dir.exist? (file_path)
          if Dir.glob("#{file_path}/*.txt").empty?
            file = get_page_response(file_link)
            file.save("#{file_path}/#{zip_file_name}")
            unzip_output = `unzip #{file_path}/#{zip_file_name} -d #{file_path}`
            raise "Failed to unzip the file: \n#{unzip_output}" unless $CHILD_STATUS.success?
            @paths << {file: file_path, transaction_date: transaction_date}
          end
        rescue Exception => e
          @paths.map { |path| delete_file(path)}
          delete_file(file_path)
          File.delete("#{file_path}/#{zip_file_name}") if Dir.glob("#{file_path}/*.ZIP").map{|e| e.split("/").last}.include? zip_file_name
          raise e.message
        end
      end
    end

    def delete_file(file_path)
      FileUtils.rm_rf(file_path) if Dir.exist?(file_path)
    end

    def parsed_url(url)
      (URI.join(MAIN_URL, url)).to_s
    end

    def initialize_folders
      folders_list = ["db", "data", "tmp"]
      folders_list.each do |folder|
        FileUtils.mkdir_p(folder)
      end
    end

    def fetch_data_via_dataset(_options = {})
      initialize_folders
      initialize_main_db
      if folders.blank?
        $stderr.puts 'Either the data folder is not set, or there are no files to process in the data folder.'
        return nil
      end
      folders.each do |record|
        folder = record[:file]
        transaction_date = record[:transaction_date]
        sampled_at = Time.parse(folder.split('/').last).utc.iso8601
        Dir.glob("#{folder}/*.txt") do |filename|
          $stderr.puts filename
          persist({File.basename(filename).gsub(".txt", "") => filename ,'sampled_at' => sampled_at, 'retrieved_at' => transaction_date})
        end
      end
    end
  end
end
