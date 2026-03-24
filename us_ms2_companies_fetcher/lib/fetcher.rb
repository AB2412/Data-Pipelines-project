require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'mechanize'

module UsMs2CompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true

    CREDENTIALS = get_bot_secret("us_ms")
    WEBSHARE_CREDENTIALS = get_bot_secret(nil, "webshare")

    def folders
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                    download_weekly_files
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

    def download_weekly_files
      paths = []
      log_info = Proc.new do |exception, try, elapsed_time, next_interval|
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      response = browser.get('https://www.sos.ms.gov/downucccorp/login.aspx')
      view_state = response.css('input#__VIEWSTATE')[0]['value']
      view_state_generator = response.css('input#__VIEWSTATEGENERATOR')[0]['value']
      event_validation = response.css('input#__EVENTVALIDATION')[0]['value']
      login_params = {
        "__VIEWSTATE" => view_state,
        "__VIEWSTATEGENERATOR" => view_state_generator,
        "__EVENTVALIDATION" => event_validation,
        "txtUserID" => CREDENTIALS["LOGIN_USERID"],
        "txtUserPW" => CREDENTIALS["LOGIN_PASSWORD"],
        "btnLogin" => "Login"
      }
      login_response = browser.post('https://www.sos.ms.gov/downucccorp/login.aspx', login_params)
      corp_filings_table = login_response.css('table table').select{|s| s.css('tr')[0].text.include? "Corp Filings"}.first
      corp_filings = corp_filings_table.css('tr').reverse
      corp_filings.each do |record|
        file_path, zip_file_name = '', ''
        next if record.css('a').count == 0

        begin
          Retriable.retriable :tries => 5, :base_interval => 240, :on_retry => log_info do
            file_link = "https://www.sos.ms.gov/downucccorp/#{record.css('a')[0]['href'].gsub('./corp', 'corp')}"
            $stderr.puts "********** File Link: #{file_link} ********************"
            folder_name = Date.strptime(file_link.split("-").last.gsub(".zip", ""), "%y%m%d").to_s
            $stderr.puts "FOLDER: #{folder_name}"
            zip_file_name = file_link.split("/").last
            file_path = "data/#{folder_name}"
            FileUtils.mkdir(file_path) unless Dir.exist? (file_path)
            if Dir.glob("#{file_path}/**/Profiles/*.xml").empty?
              file_response = browser.get(file_link)
              file_response.save("#{file_path}/#{zip_file_name}")
              unzip_output = `unzip #{file_path}/#{zip_file_name} -d #{file_path}`
              raise "Failed to unzip the file: \n#{unzip_output}" unless unzip_output.include?("inflating:")
              paths << file_path
            end
          end
        rescue Exception => e
          delete_file(file_path)
          File.delete("#{file_path}/#{zip_file_name}") if Dir.glob("#{file_path}/*.ZIP").map{|e| e.split("/").last}.include? zip_file_name
          raise e if paths.empty?
          return paths
        end
      end
      paths
    end

    def delete_file(file_path)
      FileUtils.rm_rf(file_path) if Dir.exist?(file_path)
    end


    def fetch_data_via_dataset(_options = {})
      if folders.blank?
        warn 'Either the data folder is not set, or there are no files to process in the data folder.'
        return nil
      end

      folders.each do |folder|
        sampled_at = Time.parse(folder.split('/').last).utc.iso8601
        entries = {}
        Dir.glob("#{folder}/**/Profiles/*.xml") do |filename|
          warn filename
          persist({File.basename(filename).gsub(".xml", "") => filename ,'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601})
        end
      end
    end
  end
end
