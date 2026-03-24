require_relative 'common'

def set_credentials(credentials)
  $credentials = credentials
end

def init_web(browser)
  main_page = browser.get(DATA_SOURCE, [], "", HEADER)
  redirect_href = main_page.body.force_encoding('utf-8').scan(/decodeURIComponent\('.*'\)/).first.split("'")[1] rescue nil
  second_page = if redirect_href
    browser.get("https://ontario.queue-it.net" + CGI::parse(redirect_href).keys.first, [], "", HEADER)
  else
    main_page
  end
  redirect_href = second_page.uri.to_s
  id = CGI::parse(URI.parse(redirect_href).query)['id'].first rescue nil
  cb_node = second_page.body.force_encoding('utf-8').scan(/id="AsyncWrapperW\d+/).first.split('="').last.remove('AsyncWrapper') rescue nil
  vikey = second_page.body.force_encoding('utf-8').scan(/viewInstanceKey:'[0-9a-z]+/).first.split(":'").last
  form = second_page.form
  advanced = form.keys.filter {|k| k if (k.include? 'Advanced')}.first
  advanced_node = advanced.split('-').first.remove('node')
  form = fill_common_form_values(form, vikey, cb_node, advanced)

  # Click Advanced
  form['_CBNODE_'] = advanced_node
  form['_CBNAME_'] = 'groupSelect'
  form['_CBVALUE_'] = 'groupSelect'
  second_page = browser.submit(form, nil, HEADER)
  {'form' => form, 'second_page' => second_page, 'cb_node' => cb_node, 'advanced' => advanced, 'vikey' => vikey, 'id' => id}
end

def fill_common_form_values(form, vikey, cb_node, advanced)
  if caller.to_s["fetch_gaps"]
    form[advanced] = 'N'
  else
    form[advanced] = 'Y'
    form['_CBHTMLFRAGID_'] = DateTime.now.strftime('%Q')
  end
  form['_CBASYNCUPDATE_'] = true
  form['_CBHTMLFRAG_'] = true
  form['_VIKEY_'] = vikey
  form['_CBHTMLFRAGNODEID_'] = cb_node
  form
end

def mechanize_process_company_numbers(company_numbers, company_type)
  company_numbers.each do |company_number|
    next if @fetch_company_numbers.include? company_number
    warn "\n---- Processing #{company_number} ----"
    payload = {
      "url": "https://www.appmybizaccount.gov.on.ca/onbis/master/entry.pub?applicationCode=onbis-master&businessService=registerItemSearch",
      "actions": [
        {
          "action": "type",
          "selector": { "type": "xpath", "state": "visible", "value": "//input[@id='QueryString']" },
          "text": company_number,
          "onError": "return"
        },
        {
          "action": "click",
          "selector": {
            "type": "xpath",
            "state": "visible",
            "value": "//button[normalize-space(span[text()='Search'])]"
          },
          "onError": "return"
        },
        {
          "action": "waitForSelector",
          "selector": {
            "type": "xpath",
            "state": "visible",
            "value": "//div[contains(@class, 'appRowFirst')]//a[contains(., '#{company_number}')]"
          },
          "timeout": 15,
          "onError": "return"
        },
        {
          "action": "evaluate",
          "source": "var el=document.evaluate(\"//div[contains(@class,'appRowFirst')]//a[contains(., '#{company_number}')]\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue; if(el){el.scrollIntoView({block:'center'}); el.click();}"
        },
        {
          "action": "waitForNavigation",
          "timeout": 35,
          "onError": "return"
        }
      ],
      "browserHtml": true
    }.to_json

    retries_left = 5
    success = false

    while retries_left > 0 && !success
      begin
        uri = URI("https://api.zyte.com/v1/extract")
        req = Net::HTTP::Post.new(uri)
        req.basic_auth($credentials["ZYTE_API_KEY"], "")
        req['Content-Type'] = 'application/json'
        req.body = payload
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        raise "HTTP request failed: #{res.code} #{res.message}" unless res.is_a?(Net::HTTPSuccess)

        data = JSON.parse(res.body)

        if data['statusCode'] != 200
          raise "HTML page not loaded, status code: #{data['statusCode']}"
        end

        browser_html = data['browserHtml'] || ""

        unless browser_html.include?('General Details')
          raise "Detail page not loaded for #{company_number}"
        end
        # Scrape detail page
        entry = case company_type
                when 'Partnerships'
                  scrape_partnership(company_number, browser_html)
                when 'Corporations'
                  scrape_corporation(company_number, browser_html)
                end

        warn entry
        File.write("#{@data_folder}/data.txt", "#{entry.to_json}\n", mode: 'a+')
        @fetch_company_numbers << company_number
        success = true
      rescue Timeout::ExitException
        # Re-raise timeout exceptions - let outer Retriable handle
        raise
      rescue StandardError => e
        retries_left -= 1
        if retries_left > 0
          warn "Error processing #{company_number}: #{e.message}"
          warn "Retrying #{company_number} (#{retries_left} attempts remaining)"
        else
          warn "Error processing #{company_number}: #{e.message}"
          warn "Failed to process #{company_number} after 5 attempts, moving to next company"
        end
      end
    end
  end
end

def searching_company_numbers(recent_date = true)
  warn "In the searching_company_numbers with recent_date: #{recent_date}"
  date_array = recent_date ? get_recent_dates : get_previous_month_dates
  warn "date_array are: #{date_array}"
  company_numbers = (1..9).map(&:to_s)
  begin
    Timeout::timeout(PROCESS_RUNTIME_LIMIT) {
      date_array.each do |date_string|
        company_numbers.each do |company_number|
          COMPANY_TYPES.each do |company_type|
            response = collect_company_number(date_string, company_number, company_type)
            next if (response.nil?) || (response.body.include? "No results found")
            if exceed_limit?(response)
              get_double_digit_company_numbers(company_number, date_string, company_type)
            else
              process_company_numbers(response, company_type) if response
            end
          end
        end
        save_var("previous_month_date", date_string.to_date) unless recent_date
      end
    }
  rescue Timeout::Error
    warn "Reach the run-time limit searching_company_numbers"
  end
end

def fetch_gaps_from_numbers(company_numbers)
  company_numbers.each do |company_number|
    puts "Fetch Gaps processing: #{company_number}"
    response = collect_company_number(nil, company_number, "")
    next if (response.nil?) || (response.body.include? "No results found")
    process_company_numbers(response, "") if response
  end
end

def get_recent_dates
  (Date.today - DAYS_GAP .. Date.today).map(&:to_s).map{|e|  Date.parse(e).strftime("%B %d, %Y")}
end

def get_previous_month_dates
  date_saved = get_var("previous_month_date").nil? ? Date.today - MONTHLY_GAP : Date.parse(get_var("previous_month_date"))
  start_date = date_saved - MONTHLY_GAP
  (start_date...date_saved).map(&:to_s).reverse.map{|e|  Date.parse(e).strftime("%B %d, %Y")}
end

def exceed_limit?(response)
  Nokogiri::HTML(response.body).css(".appPagerSubContainer .appPagerBanner").text.include? "200"
end

def get_double_digit_company_numbers(single_digit, date_string, company_type)
  double_digit_array = (0..9).map{ |i| single_digit.to_i * 10 + i}
  double_digit_array.each do |double_digit|
    response = collect_company_number(date_string, double_digit, company_type)
    process_company_numbers(response, company_type) if response
  end
end

def collect_company_number(date_string, company_number, company_type)
  company_type_search = company_type ? COMPANY_TYPES_SEARCH[company_type] : nil

  retries_left = 10
  result = nil

  while retries_left > 0 && result.nil?
    begin
      Mechanize.start do |browser|
        browser.read_timeout = 60
        browser.max_history = 1
        browser.set_proxy($credentials["OC_PROXY"], $credentials["OC_PROXY_PORT"], $credentials["OC_PROXY_USERNAME"], $credentials["OC_PROXY_PASSWORD"])
        init_data = init_web(browser)
        raise "init_web failed to return data" if init_data.nil?

        if caller.to_s['fetch_gaps']
          button = init_data["second_page"].parser.xpath('.//button').last
          raise "Search button not found" if button.nil? || button['id'].nil?
          select_type_node = button['id'].remove('node')
          form = init_data['form']
          form = fill_common_form_values(form, init_data['vikey'], init_data['cb_node'], init_data['advanced'])
          form['QueryString'] = company_number
          form['_CBNAME_'] = 'buttonPush'
          form['_CBNODE_'] = select_type_node
          result = browser.submit(form, nil, HEADER)
        else
          label_box = init_data['second_page'].css('div#SourceAppCode_labelBox').first
          raise "SourceAppCode label box not found" if label_box.nil? || label_box.parent.nil?
          select_type_node = label_box.parent['id']
          raise "Select type node id missing" if select_type_node.nil?
          form = init_data['form']
          # Select Type
          form = fill_common_form_values(form, init_data['vikey'], init_data['cb_node'], init_data['advanced'])
          form['SourceAppCode'] = company_type_search if company_type_search
          form['_CBNAME_'] = 'true'
          form['_CBNODE_'] = select_type_node.remove('node')
          second_page = browser.submit(form, nil, HEADER)
          warn "Started search for company: #{company_number} against date: #{date_string} company_type: #{company_type}"
          # Click search
          form = fill_common_form_values(form, init_data['vikey'], init_data['cb_node'], init_data['advanced'])
          form['QueryString'] = company_number
          form['SourceAppCode'] = company_type_search if company_type_search
          form['RegistrationDate'] = date_string if date_string
          form['_CBNAME_'] = 'buttonPush'
          search_button = second_page.parser.xpath('.//button').last
          raise "Search button not found" if search_button.nil? || search_button['id'].nil?
          form['_CBNODE_'] = search_button['id'].remove('node')
          browser.submit(form, nil, HEADER)
          third_page = browser.get(second_page.uri.to_s,[], "", HEADER)
          process_page_size(browser, form, third_page) unless date_string.nil?
          result = third_page
        end
      end
    rescue Timeout::ExitException
      # Re-raise timeout exceptions
      raise
    rescue Exception => e
      retries_left -= 1
      if retries_left > 0
        warn "Failed when collect company number #{company_number}: #{e.message}"
        warn "Retrying: #{retries_left} attempts remaining - collect_company_number"
        File.write(File.join('data/fetcher_error.txt'), "#{company_number}\n", mode: 'a+')
      else
        warn "Failed when collect company number #{company_number}: #{e.message}"
        warn "Exhausted all #{retries_left} retry attempts for #{company_number}"
        File.write(File.join('data/fetcher_error.txt'), "#{company_number}\n", mode: 'a+')
      end
    end
  end
  result
end

def process_page_size(browser, form, third_page)
  search_results = third_page.at_css("div.appSearchResults")
  raise "Search results container not found" if search_results.nil? || search_results['id'].nil?
  form['_CBHTMLFRAGID_'] = DateTime.now.strftime('%Q')
  form['_CBNAME_'] = 'pageSizeChange'
  form['_CBNODE_'] = search_results['id'].remove('node')
  form['_CBVALUE_'] = '4'
  browser.submit(form, nil, HEADER)
end

def process_company_numbers(page, company_type)
  company_numbers = page.css(".appRepeaterContent div.appMinimalBox a").map{|e| e.css("span").text.split("(").last.remove(")")}
  if caller.to_s["fetch_gaps"]
    value = page.at_xpath("//span[contains(@class, 'appMinimalLabel') and normalize-space(text())='Business Type']").next_element.text.split.last.squish
    company_type = value.pluralize
    warn "*** Company_type for fetch_gaps record: #{company_type} ***"
  end
  company_numbers.each do |company_number|
    next if datum_exists? company_number
    save_data([:uid], {uid: company_number, company_type: company_type, sampled_date: Time.now.utc.iso8601}, 'registry_queue')
  end
end

def scrape_corporation(company_number, page)
  doc = Nokogiri::HTML(page)
  labels = doc.css("span.appAttrLabel")
  values = doc.css("div.appAttrValue")

  entry = {'jurisdiction_code'=> 'ca_on', 'all_attributes' => {}, 'company_number' => company_number }
  labels.each_with_index do |label, index|
    if label.text == 'Successor Corporation'
      text = doc.css('a.appIndex1').text rescue nil
      if text
        merged_into = text.split(' (')
        entry['all_attributes']['merged_into'] = {}
        surviving_company = {'name' => merged_into.first, 'company_number' => merged_into.last.gsub(')','')}
        entry['all_attributes']['merged_into']['surviving_company'] = surviving_company
      end
    end

    next unless values[index]
    next if (values[index].blank? || values[index].text.blank?)
    value = if values[index].children.css("span.appOffScreenText").blank?
      values[index].text
    else
      values[index].children.css("span.appOffScreenText").text
    end
    next if value.blank?

    case label.text
    when 'Corporation Name'
      entry['name'] = value
    when 'Ontario Corporation Number (OCN)'
      entry['company_number'] = value
    when 'Inactive Date'
      entry['dissolution_date'] = (Date.parse value).strftime('%Y-%m-%d') rescue nil
    when 'Incorporation/Amalgamation Date'
      entry['incorporation_date'] = (Date.parse value).strftime('%Y-%m-%d')
    when 'Incorporation Date'
      entry['incorporation_date'] = (Date.parse value).strftime('%Y-%m-%d')
    when 'Amalgamation Date'
      entry['incorporation_date'] = (Date.parse value).strftime('%Y-%m-%d')
    when 'Type'
      entry['company_type'] = value
    when 'Status'
      entry['current_status'] = value
    when 'Governing Jurisdiction'
      entry['all_attributes']['Governing_Jurisdiction'] = value
    when 'Registered or Head Office Address'
      addresses = value.split(',')
      registered_address = {}
      if addresses.count > 2
        registered_address['locality'] = addresses[0]
        registered_address['region'] = addresses[1].strip
      elsif addresses.count > 1
        registered_address['locality'] = addresses[0]
      end
      registered_address['country'] = addresses[-1].strip
      registered_address.snap
      entry['registered_address'] = registered_address if validate_address(registered_address)
    when 'Principal Place of Business in Ontario'
      addresses = value.split(',')
      headquarters_address = {}
      if addresses.count > 2
       headquarters_address['locality'] = addresses[0]
        headquarters_address['region'] = addresses[1].strip
      elsif addresses.count > 1
        headquarters_address['locality'] = addresses[0]
      end
      headquarters_address['country'] = addresses[-1].strip
      headquarters_address.snap
      entry['headquarters_address'] = headquarters_address if validate_address(headquarters_address)
    end
  end
  entry['branch'] = "F" if entry['current_status'] == 'Refer to Home Jurisdiction'
  entry['all_attributes'].snap
  entry['headquarters_address'].snap if entry['headquarters_address']
  entry['registered_address'].snap if entry['registered_address']
  defaults(entry)
end

def scrape_partnership(company_number, page)
  doc = Nokogiri::HTML(page)
  labels = doc.css("span.appAttrLabel")
  values = doc.css("div.appAttrValue")
  entry = {'jurisdiction_code'=> 'ca_on', 'all_attributes' => {}, 'industry_codes' => [], 'company_number' => company_number}
  industry_code = {}

  labels.each_with_index do |label, index|
    next if label.text.blank?

    if label.text == 'Primary Activity'
      ac = doc.css("div.appAttribute").select{ |a| a.text.include? "Primary Activity"}
      primary_activity = ac.first.children.css("div.appAttribute").text rescue nil
      next if primary_activity.nil? || primary_activity.include?("Not Provided")
      code_id = primary_activity.split("-")[0].squish
      value = primary_activity.split("-")[1].squish
      scheme_code = get_scheme_code(code_id)
      if scheme_code.nil?
        entry['all_attributes']['invalid_naics_code'] = {'code' => code_id, 'name' => value}
        next
      else
        industry_code['code'] = code_id
        industry_code['name'] = value
        industry_code['code_scheme_id'] = scheme_code
      end
    end

    next if (values[index].blank? || values[index].text.blank?)
    value = if values[index].children.css("span.appOffScreenText").blank?
      values[index].text
    else
      values[index].children.css("span.appOffScreenText").text
    end

    case label.text
    when 'Firm Name'
      entry['name'] = value
    when 'Business Identification Number (BIN)'
      entry['company_number'] = value
    when 'Registration Date'
      entry['incorporation_date'] = (Date.parse value).strftime('%Y-%m-%d')
    when 'Registration Expiry Date'
      entry['dissolution_date'] = (Date.parse value).strftime('%Y-%m-%d') rescue nil
    when 'Inactive Date'
      entry['dissolution_date'] = (Date.parse value).strftime('%Y-%m-%d') rescue nil
    when 'Type'
      entry['company_type'] = value
    when 'Status'
      entry['current_status'] = value
    when 'Governing Jurisdiction'
      entry['all_attributes']['Governing_Jurisdiction'] = value
    when 'Principal Place of Business'
      addresses = value.split(',')
      headquarters_address = {}
      if addresses.count > 2
        headquarters_address['locality'] = addresses[0]
        headquarters_address['region'] = addresses[1].strip
      elsif addresses.count > 1
        headquarters_address['locality'] = addresses[0].strip
      end
      headquarters_address['country'] = addresses[-1].strip
      headquarters_address.snap
      entry['headquarters_address'] = headquarters_address if validate_address(headquarters_address)
    end
  end
  industry_code.snap
  entry['industry_codes'].push(industry_code) unless industry_code.empty?
  entry['branch'] = "F" if entry['current_status'] == 'Refer to Home Jurisdiction'
  entry['industry_codes'].snap if entry['industry_codes']
  entry['all_attributes'].snap
  entry['headquarters_address'].snap if entry['headquarters_address']
  defaults(entry)
end

def registry_queue_count
  @db.execute("select count(*) as count from registry_queue").first['count']
end

def defaults(entry)
  entry = entry.snap
  entry['dissolution_date'] = "" if entry['dissolution_date'].blank?
  entry
end
