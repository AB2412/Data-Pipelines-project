require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'net/sftp'
require 'mechanize'
require 'selenium-webdriver'

# change the JurisdictionCode with the appropriate value, i.e. UsGa, Sg, UsTx, Ro
module UsUtCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function
    DATASET_BASED = true
    CREDENTIALS = get_bot_secret("us_ut")
    PORTAL_URL = 'https://tylersftp.tylertech.com/'

    def folders
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                    crawl_aws_s3
                   end
      @folders
    end

    def unzip(file_loc, dest=nil)
      file_date = Date.parse(dest.split('/').last).to_s
      dest = "#{data_dir}/#{file_date}"
      FileUtils.mkdir_p(dest) unless Dir.glob(dest)
      command = "unzip -j -uo #{file_loc} -d #{dest}  2>&1" #pipe STDERR to STDOUT as well so we capture response
      $stderr.puts "About to unzip #{file_loc} to #{dest}"
      output = `#{command}` # backticks capture the output, unlike system, which just returns true
      raise "problem unzipping file: #{output}" unless $?.success?
      $stderr.puts output
      $stderr.puts "Successfully unzipped file" if UsUtCompaniesFetcher.verbose?
      Dir.glob(dest)
    end

    def crawl_aws_s3
      data_folders = []
      warn 'Sorting files on AWS'
      sort = `aws s3 ls s3://oc-prod-us-ut-email-downloader/downloads/ --profile us-ut | sort -k1,1 -k2,2`
      raise "Could not connect to server" if sort.blank?
      sort = sort.split("\n")

      sort.each do |name|
        file_name = name.split(' ').last
        uploaded_file_date = name.split(' ').first
        final_folder = File.join(data_dir, uploaded_file_date)
        next if File.exist? final_folder
        Dir.mkdir final_folder
        begin
          warn "downloading file #{final_folder}"
          download = `aws s3 cp s3://oc-prod-us-ut-email-downloader/downloads/#{file_name} --profile us-ut #{final_folder}`
          raise "Failed to download the file: \n#{file_name}" unless $CHILD_STATUS.success?
          unzip_output = unzip("#{final_folder}/#{file_name}", final_folder)
          data_folders.push("#{final_folder}")
        rescue Exception => e
          warn e.message
          FileUtils.rm_rf(final_folder)
        end
      end
      data_folders
    end

    def fetch_data_via_dataset(_options = {})
      if folders.blank?
        warn 'Either the data folder is not set, or there are no files to process in the data folder.'
        return nil
      end
      folders.each do |folder|
        sampled_at = Time.parse(folder.split('_').last).utc.iso8601
        entries = {}
        Dir.glob("#{folder}/*.csv") do |filename|
            warn filename
            entries[File.basename(filename, ".*")]= filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries,
                  'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
