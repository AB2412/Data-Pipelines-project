require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'open-uri'
require 'mechanize'
require 'json'
require 'retriable'
require 'parallel'

module UsFrCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function

    DATASET_BASED = true
    CREDENTIALS = get_bot_secret("fr_inpi")
    START_DATE = '2021-08-14'
    END_DATE = '2021-09-15'
    CONCURRENCY = ENV['CONCURRENCY'] || 1
    BASE_URL = "https://registre-national-entreprises.inpi.fr/api/companies?submitDateTo=#{END_DATE}&submitDateFrom=#{START_DATE}"

    $agent = Mechanize.new
    $agent.verify_mode = OpenSSL::SSL::VERIFY_NONE
    $agent.set_proxy(CREDENTIALS["OC_PROXY"], CREDENTIALS["OC_PROXY_PORT"], CREDENTIALS["OC_PROXY_KEY"])

    def fetch_data_via_dataset(_options = {})
      main_url = 'https://registre-national-entreprises.inpi.fr/api/sso/login'
      payload = { username: 'irina.stolyarova@opencorporates.com', password: 'Opencorporates21!' }
      api_token = fetch_api_token(main_url,payload,fetch_headers)
      headers = { 'Authorization' => "Bearer #{api_token}" }
      response = Retriable.retriable(tries: 5) do
        $agent.get(BASE_URL, [], nil, headers)
      end
      start_page = 1
      total_pages = response['pagination-max-page'].to_i
      pages = (start_page..total_pages).to_a
      records = []
      Parallel.each(pages, in_threads: CONCURRENCY.to_i) do |page_no|
        puts "page no: #{page_no}"
        url = BASE_URL + "&page=#{page_no}"
        begin
          response = Retriable.retriable(tries: 10) do
            $agent.get(url, [], nil, headers)
          end
          records.concat(fetch_records(response.body))
        rescue StandardError => e
          if e.is_a?(Mechanize::ResponseCodeError) && e.response_code == '401'
            puts 'Received 401 Unauthorized error. Fetching new cookie...'
            api_token = fetch_api_token(main_url,payload,fetch_headers)
            headers = { 'Authorization' => "Bearer #{api_token}" }
            retry
          else
            puts "Error occurred while fetching page #{page_no}: #{e.message}"
          end
        end
      end
      unique_records = records.uniq { |record| record["body"]["siren"] }
      fetch_response(unique_records)
    end

    def fetch_api_token(main_url,payload,headers)
      first_page_response = $agent.post(main_url, JSON.generate(payload), headers)
      response = JSON.parse(first_page_response.body)
      api_token = response['token']
    end

    def fetch_headers
      { 'Content-Type' => 'application/json' }
    end

    def fetch_records(response)
      data = JSON.parse(response)
      data.map { |record| { 'retrieved_at' => Time.now.utc.iso8601, 'body' => record } }
    end

    def fetch_response(records)
      records.each do |record|
        persist(record)
      end
    end
  end
end
