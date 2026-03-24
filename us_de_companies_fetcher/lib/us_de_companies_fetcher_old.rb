# encoding: UTF-8
require 'openc_bot'
require 'openc_bot/company_fetcher_bot'
require 'openc_bot/helpers/dates'

# you may need to require other libraries here
#
require 'nokogiri'
require 'mechanize'
require 'awesome_print'

class Array
  def strip
    self.collect{|a|a.strip}
  end
  def to_i
    self.collect{|a|a.strip.to_i}
  end
  def ecompact
    self.collect{|a|a.blank? ? nil : a}
  end
end

module UsDeCompaniesFetcher
  extend OpencBot
  extend OpencBot::CompanyFetcherBot
  extend OpencBot::Helpers::IncrementalSearch
  extend OpencBot::Helpers::Dates
  extend self # make these methods as Module methods, rather than instance ones

  SLEEP_BEFORE_HTTP_REQ = 120

  def update_data(options={})
    fetch_data
    send_run_report
  rescue Exception => e
    send_error_report(e)
    raise e
  end

  def fetch_datum(company_number, options={})
    sleep_before_http_req
    _client.get('https://delecorp.delaware.gov/tin/GINameSearch.jsp')
    _client.post_content('https://delecorp.delaware.gov/tin/controller', 'frmFileNumber' => company_number, 'action' => 'Search', 'JSPName' => 'GINAMESEARCH')
    _client.post_content('https://delecorp.delaware.gov/tin/controller', 'frmFileNumber' => company_number, 'action' => 'Get Entity Details', 'JSPName' => 'GINAMESEARCH')
  end

  def update_datum(uid, output_as_json=false,replace_existing_data=false)
    return unless raw_data = fetch_datum(uid)
    default_options = {primary_key_name => uid, :retrieved_at => Time.now}
    return unless base_processed_data = process_datum(raw_data)
    processed_data = default_options.merge(base_processed_data)
    # prepare the data for saving (converting Arrays, Hashes to json) and
    # save the original data too, as we may not extracting everything from it yet
    save_entity!(processed_data.merge(:data => raw_data))
    if output_as_json
      puts processed_data.to_json
    else
      processed_data
    end
  rescue Exception => e
    if output_as_json
      output_json_error_message(e)
    else
      rich_message = "#{e.message} updating entry with uid: #{uid}"
      $stderr.puts rich_message if verbose?
      raise $!, rich_message, $!.backtrace
    end
  end


  def process_datum( page_body )
    parse_company_page( page_body )
  end

  private
  def parse_company_page(page_body)
    doc = Nokogiri.HTML(page_body)
    raw = {}
    doc.xpath( ".//div[@id='mainBody']/table[2]/tbody/tr[count(td)=1]" ).each{|tr|
      legend = clean_text( tr )
      case legend
      when 'THIS IS NOT A STATEMENT OF GOOD STANDING'
        raw = extract_till_break_point( tr )
      when 'REGISTERED AGENT INFORMATION'
        raw.update( { 'Agent' => extract_till_break_point( tr ) } )
      end
    }
    datum = {
      retrieved_at: Time.now.utc.iso8601,
      jurisdiction_code: 'us_de',
      name: raw['Entity Name:'],
      company_number: raw['File Number:'],
      company_type: raw['Entity Kind:'],
      incorporation_date: normalise_date( raw['Incorporation Date / Formation Date:'].split("\n").first.strip ),
      all_attributes: { 'Entity Type' => raw['Entity Type:'], 'Residency' => raw['Residency:'] }
    }
    if !raw['Residency:'].blank?
      datum[:branch] = case raw['Residency:']
                       when nil, '', 'DOMESTIC'
                         nil
                       else
                         'F'
                       end
      if datum[:branch]
        if raw['State:'].blank?
          $stderr.puts 'Found a invalid jurisdiction_of_origin case'
          datum[:all_attributes][:jurisdiction_of_origin] = raw['State:']
        end
      end
    end

    if !raw['Agent'].blank? && ![nil, '', '.', 'INACTIVE AGENT ACCOUNT'].include?( raw['Agent'] )
      datum[:officers] = [
        {
          name: raw['Agent']['Name:'], 
          position: 'agent', 
          other_attributes: { 
            address: [ raw['Agent']['Address:'], raw['Agent']['City:'], raw['Agent']['County:'], raw['Agent']['State:'], raw['Agent']['Postal Code:'] ].reject(&:blank?).join(', ').strip,
            telephone_number: raw['Agent']['Phone:']
          }.reject{|k,v| v.blank? }
        }.reject{|k,v| v.blank? }
      ]
    end
    datum.reject{|k,v| v.blank? }
  end

  def extract_till_break_point( tr )
    datum = {}
    tr.xpath( 'following-sibling::*[self::tr]' ).each{|tr|
      break if tr.xpath( 'td' ).length == 1
      val = tr.xpath( 'td' ).map{|td| all_text( td ).join("\n").strip }
      datum.update( Hash[ *val ] )
    }
    datum.reject{|k,v| k.blank? }
  end

  def clean_text(raw_element)
    if raw_element.is_a?(Nokogiri::XML::Node)
      cleaned_up_text = strip_all_spaces(raw_element.inner_text)
    else
      strip_all_spaces(raw_element.text)
    end
  end

  def normalise_date( dt )
    dt.blank? ? nil : dt['0000']? nil : normalise_us_date( dt )
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
