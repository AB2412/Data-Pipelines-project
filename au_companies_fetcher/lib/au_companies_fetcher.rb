# encoding: iso-8859-1
require 'openc_bot'
require 'openc_bot/company_fetcher_bot'

# you may need to require other libraries here
#
require_relative 'mechanize_ext'

require_relative 'common'
require_relative 'csvparser'
require_relative 'apiparser'
require_relative 'csvlint'
require 'nokogiri'
require 'awesome_print'
require 'English'
require 'csv'
require 'get_process_mem'

module AuCompaniesFetcher
  extend OpencBot
  extend OpencBot::Helpers::Text
  extend OpencBot::Helpers::IncrementalSearch
  extend OpencBot::CompanyFetcherBot
  extend self # make these methods as Module methods, rather than instance ones

  RAISE_WHEN_SAVING_INVALID_RECORD = 1
  SLEEP_BEFORE_HTTP_REQ = 1
  MAX_FAILED_COUNT = 500
  #STALE_COUNT = 20000
  SAVE_RAW_DATA_ON_FILESYSTEM = 1
  @updated = 0
  CREDENTIALS = get_bot_secret("au")

  def update_data(options={})
    process_queue
    result = fetch_data
    if result.has_key?(:fetch_data_error)
      raise "\n" + JSON.pretty_generate(result)
    end
    result
  rescue Exception => e
    send_error_report(e, options)
    raise e
  end

  def send_error_report(e, options={})
    tmp = JSON.parse(e.message)
    subject = "Error running #{self.name}: #{[(tmp['fetch_data_error']['error']['message'] rescue nil), (tmp['update_stale_error']['error']['message'] rescue nil)].reject(&:blank?).join(' / ')}"
    body = "Error details: #{e.inspect}.\nBacktrace:\n#{e.backtrace}"
    send_report(:subject => subject, :body => body)
    report_run_to_oc(:output => body, :status_code => '0', :ended_at => Time.now.to_s, :started_at => options[:started_at])
  end

  def exception_to_json(ex)
    {'klass' => ex.class.to_s, 'message' => ex.message, 'backtrace' => ex.backtrace}
  end

  def get_json_body(page)
    doc = Nokogiri::HTML(page)
    doc.at('pre')&.text
  end

  def fetch_data
    original_count = record_count
    res = {}
    if use_alpha_search
      fetch_data_via_alpha_search
      res[:run_type] = 'alpha'
    else
      check_and_load_from_dump
      res[:run_type] = 'opendata'
      res[:output] = ''
    end
    res.merge(records_counter(original_count))
  rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance => ex
    { run_type: 'opendata/incremental', fetch_data_output: ex.class.to_s }.merge(records_counter(original_count))
  rescue Exception => ex
    { run_type: 'opendata/incremental', :fetch_data_error => {'error' => exception_to_json(ex)}}.merge(records_counter(original_count))
  end

  def check_and_load_from_dump
    browser = Mechanize.new do |b|
      b.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:28.0) Gecko/20100101 Firefox/28.0'
      b.read_timeout = 2400
      b.max_history = 1
      b.verify_mode = OpenSSL::SSL::VERIFY_NONE
      b.set_proxy(CREDENTIALS["ZYTE_API_HOST"], CREDENTIALS["ZYTE_API_PORT"], CREDENTIALS["ZYTE_API_KEY"], '')
    end
    browser.request_headers = {"Zyte-Browser-Html" => "true"}
    page = browser.get('https://data.gov.au/api/3/action/package_show?id=7b8656f9-606d-4337-af29-66b89b2eeefb').body
    json_body = get_json_body(page)
    location = parse_json_location(json_body)
    if get_var(location[:published_date].to_i.to_s).blank?
      $stderr.puts "Downloading & importing files from: #{location}"
      new_modified_to_queue(download_opendata(location[:download_url]), location[:published_date])
      save_var(location[:published_date].to_i.to_s, 'complete')
    else
      $stderr.puts 'Already processed the latest open data file'
    end
    process_queue
  end

  def record_updated?(company_number, record_status)
    company_status_mapping[record_status] != @db_records[company_number]
  end

  def new_modified_to_queue(filename, published_date)
    @db_records = {}
    select('company_number, current_status from ocdata').map{|s| @db_records[s['company_number']] = s['current_status']}
    CSVLint.new(infile: filename).to_csv do |raw|
      next if ['RSVD', 'RSVN'].include?(raw['Type']) || ['RSVD', 'APPD'].include?(raw['Status'])
      acn = raw['ACN'].size == 9 ? raw['ACN'] : "%09d" % raw['ACN']
      unless datum_exists?(acn)
        save_data([:company_number], {company_number: acn, published_date: published_date, type: 'New'},'queue')
      end

      unless raw['Modified since last report'].blank?
        save_data([:company_number], {company_number: acn, published_date: published_date, type: 'Modified'},'queue')
      else
        if record_updated?(acn, raw['Status'])
          save_data([:company_number], {company_number: acn, published_date: published_date, type: 'Modified'},'queue')
        end
      end
    end
  end

  def process_queue
    select('* from queue').each do |tuple|
      update_datum(tuple['company_number'])
      if tuple['type'] == 'Modified'
        @updated += 1
      end
      sqlite_magic_connection.execute('delete from queue where company_number=?', tuple['company_number'])
    end
  end

  def fetch_datum(company_number, options = {})
    $stderr.puts 'Processing: ' + company_number
    #raise OpencBot::OutOfPermittedHours.new("Request at #{Time.now} is not out business hours (#{allowed_hours})") if in_prohibited_time? && caller.to_s['update_data']
    sleep_before_http_req
    browser = Mechanize.new do |b|
      b.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:28.0) Gecko/20100101 Firefox/28.0'
      b.read_timeout = 3600
      b.max_history = 1
      b.verify_mode = OpenSSL::SSL::VERIFY_NONE
      b.add_auth('https://www.gateway.asic.gov.au', 'ASICM2MRA@OPENCORPORATES.COM','k8s%hqe890')
      b.set_proxy(CREDENTIALS["ZYTE_API_HOST"], CREDENTIALS["ZYTE_API_PORT"], CREDENTIALS["ZYTE_API_KEY"], '')
    end
    page = browser.post('https://www.gateway.asic.gov.au/gateway/ExternalGetNniNamePortV3', IO.read('lib/ExternalGetNniNamePortV3_Body.xml').sub('<uri:nniNumber></uri:nniNumber>',"<uri:nniNumber>#{company_number}</uri:nniNumber>"))
    IO.write(data_dir + '/details.xml', (Nokogiri::XML(page.body).to_xml rescue ''))
    if page.body['business.document.header.types:errorCode>']
      IO.write(data_dir + '/error_response.xml', page.body)
      doc = Nokogiri::XML(page.body)
      doc.remove_namespaces!
      error_code = clean_text(doc.xpath(".//messageEvent/errorCode/text()"))
      error_desc = clean_text(doc.xpath(".//messageEvent/description/text()"))
      if ['00001','00047'].include?(error_code)
        $stderr.puts "#{Time.now.utc.iso8601} - Registry could not process request because of error: #{error_code} - description: #{error_desc}"
        return nil
      else
        IO.write(data_dir + "/invalid_response_#{company_number}.xml", page.body)
        $stderr.puts "#{Time.now.utc.iso8601} - Registry could not process request because of error: #{error_code} - description: #{error_desc}"
        return nil
      end
    end
    if page.body['>Service availability<'] || page.body['<env:Fault>']
      IO.write(data_dir + "/invalid_response_#{company_number}.xml", page.body)
      $stderr.puts "#{Time.now.utc.iso8601} - Registry is unavailable to process request: #{company_number}"
      return nil
    end
    page.body
  rescue SocketError, Net::HTTP::Persistent::Error, Net::HTTPFatalError
    IO.write(data_dir + '/invalid_details.xml', (page.body rescue ''))
    $stderr.puts 'Could not process request for the identifier: ' + company_number
  rescue Mechanize::ResponseCodeError => ex
    IO.write(data_dir + '/invalid_details.xml', (page.body rescue ''))
    if ['500', '503', '504', '400'].include?(ex.response_code)
      $stderr.puts 'Could not process request for the identifier: ' + company_number
      return nil
    else
      raise ex
    end
  end

  def process_datum(data_hash)
    APIParser.new(data_hash).encapsulate_as_per_schema
  end

  private

  def records_counter(original_count)
    added = record_count - original_count
    updated = @updated - added
    {added: added, updated: updated}
  end

  def parse_json_location(page_body)
    doc = JSON.parse(page_body)['result']['resources']
    tmp = doc.select{|res| res['format'] == 'CSV'}.map do |res|
      {
        url: res['url'],
        published_date: Time.parse(res['last_modified']),
        download_url: res['url']
      }
    end
    tmp && tmp.sort_by { |item| item[:published_date] }.last
  end

  def parse_csv_location(page_body)
    doc = Nokogiri::HTML(page_body)
    tmp = doc.xpath(".//a[span[@data-format] and following-sibling::*[1][self::p][contains(text(),'Company Dataset extract as')]]").map do |anchor|
      {
        url: 'https://data.gov.au' + anchor.attr('href').to_s,
        published_date: Time.parse(clean_text(anchor.xpath('following-sibling::*[1][self::p]')).sub('Company data extract as at', '')),
        download_url: anchor.xpath('following-sibling::*[2][self::div]/ul/li[2]/a').attr('href').to_s
      }
    end
    tmp && tmp.sort_by { |item| item[:published_date] }.last
  end
end
