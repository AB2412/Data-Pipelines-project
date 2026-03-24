require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'selenium-webdriver'

module UsId2CompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true
    CREDENTIALS = get_bot_secret('us_id2')

    def folders
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                     download_data
                   end
      @folders
    end

    def download_data
      data_folders = []
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless')
      tmp_folder = "#{Dir.getwd}/tmp/#{Date.today.strftime('%Y-%m-%d')}"

      download_prefs = {
          prompt_for_download: false,
          default_directory: tmp_folder
        }
      options.add_preference(:download, download_prefs)

      driver = Selenium::WebDriver.for :chrome, options: options
      driver.manage.window.resize_to(1920, 3000)
      driver.navigate.to 'https://sosbiz.idaho.gov/auth?from=/data-requests'

      sleep 5
      
      username_field = driver.find_element(name: 'username')
      password_field = driver.find_element(name: 'password')
      username_field.send_keys(CREDENTIALS['USERNAME'])
      password_field.send_keys(CREDENTIALS['PASSWORD'])
      login_button = driver.find_element(:css, 'button.btn-raised.btn-light-primary.submit')
      login_button.click
      sleep 5

      driver.navigate.to 'https://sosbiz.idaho.gov/data-requests'
      sleep 5
      
      list_items = driver.find_elements(:tag_name, 'li')
      list_items.each do |item|
        next unless item.text.include?('Completed Request')
        button = item.find_elements(:tag_name, 'button').last
        button.click
        sleep 5
        reports_list_div = driver.find_element(:css, 'div.reports-list')
        date = reports_list_div.find_element(:css, 'span.date').text
        file_date = Date.strptime(date, '%m/%d/%Y')
        formatted_date = file_date.strftime('%Y-%m-%d')
        formatted_date_folder = "#{data_dir}/#{formatted_date}"
        next if Dir.exist?(formatted_date_folder)
        begin
          Dir.mkdir(formatted_date_folder)
          puts "Download data for #{formatted_date}"
          download_button = reports_list_div.find_element(:tag_name, 'button')
          download_button.click
          sleep 30
          zip_file = Dir.glob("#{tmp_folder}/*.zip").first
          unzip(zip_file, formatted_date_folder)
          data_folders.push formatted_date_folder
        rescue Exception => e
          puts "Error downloading data for #{formatted_date}: #{e.message}"
          FileUtils.rm_rf(formatted_date_folder)
          raise e
        end
      end
      data_folders
    end

    def unzip(file_loc, dest=nil)
      dest ||= file_loc.to_s.sub(/.zip$/,'')
      Dir.mkdir(dest) unless Dir.glob(dest)
      command = "unzip -uo #{file_loc} -d #{dest}  2>&1"
      $stderr.puts "About to unzip #{file_loc} to #{dest}"
      output = `#{command}`
      raise "problem unzipping file: #{output}" unless $?.success?
      $stderr.puts "Successfully unzipped file"
      Dir.entries( dest )
    end

    def fetch_data_via_dataset(_options = {})
      if folders.blank?
        warn 'Either the data folder is not set, or there are no files to process in the data folder.'
        return nil
      end

      folders.each do |folder|
        sampled_at = Time.parse(folder.split('_').last).utc.iso8601
        entries = {}
        Dir.glob("#{folder}/*.txt") do |filename|
            warn filename
            entries[File.basename(filename, '.txt')] = filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries,
                  'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
