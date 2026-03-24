require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'

require 'rubygems'
require 'mechanize'
require 'logger'
require 'net/http'


# change the JurisdictionCode with the appropriate value, i.e. UsGa, Sg, UsTx, Ro
module IlCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true

    def folders
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                    website_crawler
                   end
      @folders
    end

    def website_crawler
      folders = []
      agent = Mechanize.new
      agent.log = Logger.new "mech.log"
      agent.pluggable_parser.default = Mechanize::Download
      agent.request_headers = {
        'authority' =>'data.gov.il',
        'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        'accept-language' => 'en-IN,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,en-GB;q=0.6,en-US;q=0.5',
        'referer' => 'https://data.gov.il/dataset/ica_companies',
        'cookie' => 'rbzid=G1uWW7c3QzYel78kANn8EhrV8i5dRn81J0Ty2vzorEGqo3lGFxz/jnlEdz2RqKxwdNpgL9tbd2S0XL6Nks61Aiy4ILNAjlqIYs5+yIkTUogQJ8rkDnT8QUsuieX+5itqn2AhvJSe5XPzGyMlWaicBIIZHqHWQDWSw23iDbsL0BnKCTQ+rv6TAH2aZ/vUQCpOazZ3gb1TtimIi/ZC1mRS3JQV+LpF3ZWfkOVZHD454EaG255mZF6M3rOulZw+VZGvZVIdmlMQsx1oGouKjd7vqA==; rbzsessionid=a940ea7f0e8a6f1a4396a9bb3fe84a38; _gid=GA1.3.638453525.1662460462; _gat=1; _gat_UA-73172242-1=1; _ga_HNM3Z0EMD9=GS1.1.1662460462.5.0.1662460462.0.0.0; _ga=GA1.1.1757780258.1661361606',
        'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36'
      }

      warn "Loading homepage for ica companies..."
      page = agent.get 'https://data.gov.il/dataset/ica_companies'
      puts page.search('//*[@id="dataset-resources"]/ul/li[1]/p/font[1]/font')

      warn "Downloading file for ica companies"
      download_link = page.at('//*[@id="dataset-resources"]/ul/li[1]/div/a[2]')
      download_link = agent.resolve(download_link['href'])

      ica_companies_csv_page = agent.get(download_link)
      ica_company_date = ica_companies_csv_page.header['last-modified'].split(',')[1]

      ica_company_date = Date.parse(ica_company_date)
      final_folder = File.join(data_dir, "#{ica_company_date}")

      if (File.exist? final_folder)
        warn "The folder exists but the contents do not match. Deleting #{final_folder} ..."
        FileUtils.rm_rf(final_folder)
        warn "Existing folder deleted successfully. Creating new folder #{final_folder} ..."
      end
      Dir.mkdir final_folder
      ica_companies_csv_page.save("#{final_folder}/ica_companies.csv")


      warn "Loading homepage for ica partnerships..."
      page = agent.get 'https://data.gov.il/dataset/ica_partnerships'
      puts page.search('//*[@id="dataset-resources"]/ul/li[1]/p/font[1]/font')

      warn "Downloading file for ica partnership"
      download_link = page.at('//*[@id="dataset-resources"]/ul/li[1]/div/a[2]')
      download_link = agent.resolve(download_link['href'])

      ica_partnership_csv_page = agent.get(download_link)
      ica_partnership_date = ica_partnership_csv_page.header['last-modified'].split(',')[1]
      
      ica_partnership_date = Date.parse(ica_partnership_date)
      ica_partnership_csv_page.save("#{final_folder}/ica_partnership.csv")

      folders.push(final_folder)
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
          # exclude filenames here if needed
            warn filename
            entries[File.basename(filename, ".*").upcase]= filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries,
                  'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
