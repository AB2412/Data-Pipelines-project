# encoding: UTF-8
require 'openc_bot'
require 'openc_bot/company_fetcher_bot'
require 'openc_bot/helpers/dates'

# you may need to require other libraries here
#
require 'nokogiri'
require_relative 'mechanize'
require 'awesome_print'

class Array
  def strip
    self.collect{|a|a.strip}
  end
end

class Hash
  def compact
    self.delete_if{|k,v| [nil, [], {}, '', ',', '.', 'n/a', '&nbsp', 'NONE', 'none', 'No address' ].include?(v) }
  end
end


module BbCompaniesFetcher
  extend OpencBot
  # This adds the CompanyFetcherBot functionality
  extend OpencBot::CompanyFetcherBot
  # uncomment to get Date helper methods
  extend OpencBot::Helpers::Dates
  extend self # make these methods as Module methods, rather than instance ones

  MAX_FAILED_COUNT = 30
  STALE_COUNT = 3500
  RAISE_WHEN_SAVING_INVALID_RECORD = 1
  SLEEP_BEFORE_HTTP_REQ = 5
  SAVE_RAW_DATA_ON_FILESYSTEM = 1
  TIMEZONE = 'America/Barbados'
  USE_ALPHA_SEARCH = true
  LIMIT = 20
  @updated = 0

  def letters_and_numbers
    ['']
  end

  def fetch_data
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
  rescue OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance, Interrupt => e
    {:added => (record_count - original_count), :updated => @updated, :output => e.message}
  end

  def fetch_data_via_alpha_search(options={})
    starting_term = options[:starting_term]||get_var('starting_term')
    each_search_term(starting_term) do |term|
      save_var('starting_term', term)
      search_for_entities_for_term(term, options)
    end
    # reset pointer
    save_var('starting_term',nil)
  end

  def update_stale
  end

  def search_for_entities_for_term(term, options = {})
    limitstart = get_var('limitstart') || 0
    loop do
      browser = Mechanize.new { |b|
        b.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:28.0) Gecko/20100101 Firefox/28.0'
        b.read_timeout = 2400
        b.max_history = 1
        b.retry_change_requests = true
        b.verify_mode = OpenSSL::SSL::VERIFY_NONE
      }
      page = browser.get("http://caipo.gov.bb/site/index.php/search/search-our-database?format=html&reset=false&search=search...&limit=#{LIMIT}&limitstart=#{limitstart}")
      IO.write(data_dir + '/list.html', page.body)
      slugs = page.parser.css('a.joodb_titletink').map do |anchor| anchor.attr('href').to_s end
      if slugs.blank?
        save_var('slugstart', nil)
      else
        slug_start = get_var('slugstart') || 0
        slugs[slug_start..-1].each_with_index do |slug, idx|
          update_datum("http://www.caipo.gov.bb#{ slug }")
          slug_start += 1
          save_var('slugstart', slug_start)
        end
        save_var('slugstart', nil)
        limitstart += LIMIT
        save_var('limitstart', limitstart)
      end
      break if !page.body['>End</a>']
    end
    save_var('limitstart', nil)
    save_var('slugstart', nil)
  end

  def fetch_datum(company_number, options = {})
    raise OpencBot::OutOfPermittedHours.new("Request at #{ Time.now.utc.iso8601 } is not out business hours (#{allowed_hours})") if in_prohibited_time? && caller.to_s['update_data']
    sleep_before_http_req
    browser = Mechanize.new { |b|
      b.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:28.0) Gecko/20100101 Firefox/28.0'
      b.read_timeout = 2400
      b.max_history=1
      b.retry_change_requests = true
      b.verify_mode = OpenSSL::SSL::VERIFY_NONE
    }
    registry_url = company_number[/^http/]? company_number : (select('registry_url from ocdata where company_number=?', company_number).first['registry_url'] rescue nil)
    if registry_url.blank?
      $stderr.puts 'Could not find valid registry_url'
    else
      $stderr.puts "Processing: #{URI.parse(registry_url).path.split('/').last}"
      page = browser.get(registry_url)
      IO.write(data_dir + '/details.html', page.body)
      { company_page: page.body, retrieved_at: Time.now.utc.iso8601, registry_url: page.uri.to_s }
    end
  rescue Mechanize::ResponseReadError, Mechanize::ResponseCodeError, Net::HTTP::Persistent::Error => exception
    $stderr.puts 'Source could not process request'
    return nil
  end

  def process_datum(entry)
    datum = parse_company_page(entry)
    unless datum.blank?
      @updated += 1 if datum_exists?(datum[:company_number]) && caller.to_s['update_data']
      datum
    end
  end

  private
  def parse_search_listing(page)
    page.parser.css('a.joodb_titletink').map{|anchor|
      { name: clean_text(anchor), slug: anchor.attr('href').to_s }
    }
  end

  def parse_company_page(entry)
    IO.write(data_dir + '/details.html', entry[:company_page])
    doc = Nokogiri::HTML(entry[:company_page])
    datum = {
      retrieved_at: (entry['retrieved_at'] || Time.now.utc.iso8601),
      jurisdiction_code: 'bb',
      all_attributes: {},
      registry_url: entry[:registry_url],
      name: doc.css('div.joodb > table tr > th > h4').inner_text.strip
    }
    Nokogiri::HTML(entry[:company_page]).css('div.database-article > table div').each do |div|
      value = clean_text(div.xpath('./text()'))
      case legend = clean_text(div.xpath('./strong/text()'))
      when 'Name:'
        datum[:name] = begin
                         if datum[:name].blank? && div.inner_text['This email address is']
                           tmp = Nokogiri::HTML.parse(div.inner_html.split("\t").select{|item| item['var addy_'] }.first.split('=')[1].split(';document').first.strip).text.split('+').strip
                           tmp.map{|item| item.gsub(/^'|'$/,'')}.join('')
                         else
                           datum[:name]
                         end
                       end
      when 'Number:'
        datum[:company_number] = value
      when 'Category:'
        datum[:company_type] = value
      when 'Date Registered / Incorporated:'
        datum[:incorporation_date] = normalise_us_date(value)
      when nil, ''
        nil
      else
        raise 'Unhandled legend: ' + legend.to_json
      end
    end
    if datum[:name].blank? || datum[:company_number].blank?
      $stderr.puts 'Could not find valid legal entity details'
      return nil
    end
    datum.compact
  end

  def clean_text(raw_element)
    if raw_element.is_a?(Nokogiri::XML::Node)
      cleaned_up_text = strip_all_spaces(raw_element.inner_text)
    else
      strip_all_spaces(raw_element.text)
    end
  end

  def all_text(str)
    ret = []
    if str.kind_of? (Nokogiri::XML::Element)
      tmp = []
      str.children().each{|st|
        tmp << all_text(st)
      } unless str.name == 'script' or str.name == 'style'
      ret << tmp
    elsif str.kind_of? (Nokogiri::XML::NodeSet)
      str.collect().each{|st|
        ret << all_text(st)
      }
    elsif str.kind_of? (Nokogiri::XML::Text)
      ret << clean_text(str)
    end
    return ret.flatten
  end
end
