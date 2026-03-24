require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'fileutils'
require 'mechanize'
require 'httparty'

module UsMt2CompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true
    DATA_SOURCE = "https://biz.sosmt.gov/api/Auth/login"
    CREDENTIALS = get_bot_secret("us_mt2")
    WEBSHARE_CREDENTIALS = get_bot_secret(nil, "webshare")
    LOGIN_CREDENTIALS = { username: CREDENTIALS["USERNAME"], password: CREDENTIALS["PASSWORD"] }

    def folders
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                    scrape_website_for_files
                   end
      @folders
    end

    def request_with_retries(url, headers, params={}, request_type='get')
      log_info = Proc.new do |exception, try, elapsed_time, next_interval|
        $stderr.puts "Processing failed (request_with_retries) - #{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
        if try % 2 == 0
          warn "********* Proxy is switching **********"
          HTTParty::Basement.http_proxy(WEBSHARE_CREDENTIALS["OC_PROXY"], WEBSHARE_CREDENTIALS["OC_PROXY_PORT"], WEBSHARE_CREDENTIALS["OC_PROXY_USERNAME"], WEBSHARE_CREDENTIALS["OC_PROXY_PASSWORD"])
        end
      end

      Retriable.retriable tries: 10, base_interval: 20, on_retry: log_info do
        warn "******** Request hitting for: #{url} *********"
        if request_type == 'get'
          response = HTTParty.get(url, headers: headers, follow_redirects: false)
        elsif request_type == 'post'
          response = HTTParty.post(url, :body => params.to_json, :headers => headers, :verify => false)
        end
        raise if response.response.code != "200"
        response
      end
    end

    def scrape_website_for_files
      outfolders = []
      processed_urls = []
      @final_folder = nil
      warn "Start scraping website..."
      warn "Logging in..."
      headers = { "Content-Type"=> "application/json", "user-agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"}

      log_info = Proc.new do |exception, try, elapsed_time, next_interval|
        $stderr.puts "Processing failed (Main function) - #{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      Retriable.retriable tries: 5, base_interval: 30, on_retry: log_info do
        HTTParty::Basement.http_proxy(WEBSHARE_CREDENTIALS["OC_PROXY"], WEBSHARE_CREDENTIALS["OC_PROXY_PORT"], WEBSHARE_CREDENTIALS["OC_PROXY_USERNAME"], WEBSHARE_CREDENTIALS["OC_PROXY_PASSWORD"])
        login = request_with_retries(DATA_SOURCE, headers, LOGIN_CREDENTIALS, 'post')
        headers.update({"path"=>"/api/Data-Request/GetList" , "authorization" => login.parsed_response["Item2"]["ID"]})
        sleep(20)
        file_list = request_with_retries("https://biz.sosmt.gov/api/Data-Request/GetList", headers)

        file_list.parsed_response.each do |file|
          if file["STATUS_RO"] == "Completed Request" and file["NAME"] == "Active New Business Entity Report"
            data_request_id = file["DATA_REQUEST_ID"]
            form_definition_id = file["FORM_DEFINITION_ID"]
            last_modified_date = Date.parse(file["LAST_MODIFIED_DATE"]).strftime("%Y-%m-%d")
            @final_folder = "#{data_dir}/#{last_modified_date}"
            next if Dir.exist?(@final_folder)
            sleep(20)
            payload_url = "https://biz.sosmt.gov/api/Report/#{form_definition_id}/#{data_request_id}"
            next if processed_urls.include? payload_url
            download_file_payload = request_with_retries(payload_url, headers).parsed_response
            processed_urls << payload_url
            next if download_file_payload.empty?

            Dir.mkdir(@final_folder)
            filename = "EntityReport-#{last_modified_date}.zip"
            warn "Downloading File from #{last_modified_date}..."
            sleep(20)
            File.open("#{@final_folder}/#{filename}", "w") do |file|
              file_response = request_with_retries("https://biz.sosmt.gov/api/Report/getbyreportobject", headers, download_file_payload[1], 'post')
              file.write(file_response)
            end

            warn "Data file for #{last_modified_date} has been downloaded successfully, now unzipping #{filename}"

            unzip_output = `unzip #{@final_folder}/#{filename} -d #{@final_folder}`

            raise "Failed to unzip the file: \n#{unzip_output}" unless $CHILD_STATUS.success?

            FileUtils.mv("#{@final_folder}/DataRequest.csv", "#{@final_folder}/#{filename.sub(".zip", ".csv")}")

            outfolders.push(@final_folder)
          end
        end
        outfolders.sort
      rescue StandardError => e
        FileUtils.rm_rf(@final_folder) if Dir.exist?(@final_folder)
        raise e
      end
    end

    def fetch_data_via_dataset(_options = {})
      if folders.blank?
        warn 'Either the data folder is not set, or there are no files to process in the data folder.'
        return nil
      end
      folders.each do |folder|
        sampled_at = Time.parse(folder.split('/').last).utc.iso8601
        entries = {}
        Dir.glob("#{folder}/*.csv") do |filename|
          warn filename
          entries[File.basename(filename, '.*')] = filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries,
                  'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
