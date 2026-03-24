# encoding: UTF-8
# NB You should run the bot in a directory containing a Gemfile, which should contain the following line:
# gem 'openc_external_bot', :git => 'git@github.com:openc/openc_external_bot.git'
# so that you can, collect the gems using bundler.
require 'openc_external_bot'
require 'httpclient'
require 'csv'
require 'nokogiri'

module AsicGazette
  extend OpencExternalBot
  extend self # make these methods as Module methods, rather than instance ones

  def export_data(params={:offset => 0})
    # This is the basic functionality for exporting the data from the database. By default the data
    # table (what is created when you save_data) is called ocdata, but it can be called anything else,
    # and the query can be more complex, returning, for example, only the most recent results.
    # By default the importer will page through the data, supplying an offset equal to the aggregate
    # number of results already received. It will stop requesting data when an empty array is returned
    sql_query = "ocdata.* from ocdata LIMIT 200 OFFSET #{params[:offset]}"
    select_data(sql_query).collect do |raw_datum|
      # raw_datum will be a Hash of field names (as symbols) for the keys and the values for each field.
      # It should be converted to the format necessary for importing into OpenCorporates, perhaps by
      # using a prepare_for_export method.
      prepare_for_export(raw_datum)
    end
  end

  def fetch_data_for_notices
    sql_query = "ocdata.* from ocdata WHERE retrieved_at IS NULL LIMIT 500"
    select_data(sql_query).each do |notice|
      begin
      populate_details(notice)
      rescue Exception => e
        puts "Exception #{e.inspect} raised populating details for notice:\n #{notice.inspect}"
        puts e.backtrace.inspect
      end
      sleep 5
    end
  end

  # This can be run from the command line to get old notices with something like:
  # (1..10).each { |i| puts "About to get gazette notices with offset of #{i} (#{Date.today - i*14})"; AsicGazette.search_for_notices(:start_date => (Date.today - 14 - i*14).strftime('%d/%m/%Y'), :end_date => (Date.today - i*14).strftime('%d/%m/%Y'1))  }
  def search_for_notices(params={})
    start_date = params[:start_date] || (Date.today - 2).strftime('%d/%m/%Y')
    end_date = params[:end_date] || Date.today.strftime('%d/%m/%Y')
    p url = "https://insolvencynotices.asic.gov.au/browsesearch-notices?appointment=All&noticepurpose=All&noticestate=All&deregistration=true&publishedform=#{start_date}&publishedto=#{end_date}"
    url += '&archvd=0' if params[:include_archived]
    search_results = client.get_content(url)
    viewstate = Nokogiri.HTML(search_results).at('input[@name="__VIEWSTATE"]')[:value]
    i = 2
    csv_data = nil # define outside block
    loop do
      sleep 2
      csv_data = client.post_content(url, '__EVENTTARGET' => 'ctl00$ctl00$ctl00$ctl00$ContentPlaceHolderDefault$INWMasterContentPlaceHolder$INWPageContentPlaceHolder$ucNoticeResult$btnCSVExport', 
                                          '__VIEWSTATE' => viewstate, 
                                          '__LASTFOCUS' => nil, 
                                          '__VIEWSTATEENCRYPTED' => nil)
      data = CSV.parse(csv_data.gsub('"',''), :headers=>true, :header_converters =>:symbol).collect{|r| r.to_hash} 
      p data if verbose?
      break if data.empty?
      # nb the identifier is the notice number and may relate to several companies
      data.each do |datum|
        insert_or_update([:identifier, :acn], datum)
      end
      #save_data([:identifier, :acn], data)
      unless last_page_link = Nokogiri.HTML(search_results).at("a[@href*='Page$Last']")
        puts "No more pages for this search"
        break
      end
      puts "About to get page #{i} from #{url}" if verbose?
      search_results = client.post_content(url, '__EVENTARGUMENT'=>"Page$#{i}", 
                         '__VIEWSTATE' => viewstate, 
                         #'archvd' => '0',
                         '__EVENTTARGET'=>'ctl00$ctl00$ctl00$ctl00$ContentPlaceHolderDefault$INWMasterContentPlaceHolder$INWPageContentPlaceHolder$ucNoticeResult$lvNoticeList',
                         '__LASTFOCUS'=>nil,'__VIEWSTATEENCRYPTED'=>nil)
      viewstate = Nokogiri.HTML(search_results).at('input[@name="__VIEWSTATE"]')[:value]
      i += 1
    end
  rescue Exception => e
    puts "Exception (#{e.inspect}) getting/parsing data from page #{i}: csv_data = #{csv_data.inspect}.\n Backtrace: #{e.backtrace}"
  end

  def parse_notice_page(page)
    doc = Nokogiri.HTML(page)
    notice_section = doc.at('#ContentPlaceHolderDefault_INWMasterContentPlaceHolder_INWPageContentPlaceHolder_ucNoticeDetails_ucNoticeOutput_xmlxsltHolder')
    notice_body = notice_section.at('div.boxinnerbody')
    {:notice_html => notice_section.inner_html.strip,
     :notice_data => data_from_notice(notice_body).to_json}
  end

  def populate_details(notice)
    result = parse_notice_page(client.get_content(notice[:notice_url]))
    result.merge!(:identifier => notice[:identifier], :acn => notice[:acn], :retrieved_at => Time.now.to_s)
    #p result
    insert_or_update([:identifier, :acn], result)
  end

  def prepare_for_export(raw_data)
    # do something here to convert the raw data from the database (if you are using one) into
    # the form required by the export.
  end

  def update_data
    search_for_notices
    fetch_data_for_notices
    save_run_report(:status => 'success')
  end

  private
  def client
    @client ||= HTTPClient.new
  end

  def data_from_notice(notice_body)
    res = {}
    notice_body.search('div').to_a.each_slice(2){|a,b| res[a.inner_text] = b.inner_html if a[:class][/boxinnersub/] and b and b[:class][/boxinnercontent/]   }
    res
  end

end
