# encoding: iso-8859-1
require 'nokogiri'
require 'openc_bot/helpers/text'

INVALID_FIELDS = [nil, [], {}, '', '00000000000', 'RESTRICTED', 'NONE'].freeze

# Monkeypatch Array
class Array
  def strip
    collect { |string| string.class.name == 'String' ? string.strip : string }
  end

  def compact
    delete_if do |item|
      INVALID_FIELDS.include?(item) || item =~ /^[*,-.\s]+$/
    end
  end
end

# Monkeypatch Hash
class Hash
  def strip
    map do |k, v|
      if v.blank?
        Hash[k, (v.class.name == 'String' ? v.strip : v)]
      else
        Hash[k, v]
      end
    end.inject(&:update)
  end

  def compact
    delete_if do |_k, v|
      INVALID_FIELDS.include?(v) || v =~ /^[*,-.\s]+$/
    end
  end
end

def clean_text(raw_element)
  if raw_element.is_a?(Nokogiri::XML::Node)
    raw_element.inner_text.to_s.gsub(/\u{a0}/, ' ').strip
  else # assume it's a string or nil
    raw_element.text.to_s.gsub(/\u{a0}/, ' ').strip
  end
end

def all_text(str)
  ret = []
  if str.is_a?(Nokogiri::XML::Element)
    tmp = []
    str.children.each do |st|
      tmp << all_text(st)
    end unless str.name == 'script'
    ret << tmp
  elsif str.is_a?(Nokogiri::XML::NodeSet)
    str.collect.each do |st|
      ret << all_text(st)
    end
  elsif str.is_a?(Nokogiri::XML::Text)
    ret << clean_text(str)
  end
  ret.flatten
end

def cleaned_address(address)
  if address.key?(:street_address) || address.key?(:postal_code) || (address.key?(:locality) && address.key?(:country))
    address
  else
    tmp = address.values.join(', ')
    (tmp.size <= 3 ? nil : tmp)
  end
end

def company_status_mapping
  {'APPR' => 'Approved (Trust)', 'ARCH' => 'Business Names - Archived', 'ASOS' => 'Association Strike Off Status', 'CNCL' => 'Cancelled', 'CONV' => 'Converted (Trust)', 'DISS' => 'Dissolved By Special Act Of Parliament', 'DIV3' => 'Organisation Transferred Registration Via Div3', 'DMNT' => 'Dormant', 'DRGD' => 'Deregistered', 'EXAA' => 'External Administration - Associations', 'EXAD' => 'Externally Administered', 'NOAC' => 'Not Active', 'NRGD' => 'Not Registered', 'PEND' => 'Pending - Schemes', 'PROV' => 'Provisional', 'REGD' => 'Registered', 'REXP' => 'Business Name Expired', 'RMVD' => 'Business Names - Removed', 'SOFF' => 'Strike-Off Action In Progress', 'WDUP' => 'Winding Up - Managed Investments Schemes', 'WDPI' => 'Winding Up - Prescribed Interest Schemes', 'RSVD' => 'Reserved name', 'APPD' => 'Approved name reservation'}
end

def download_opendata(url)
  filename = url.split('/').last
  `rm -rf data/#{filename}; rm -rf data/#{filename}`
  wget_out = `wget #{url} -O data/#{filename}`
  if $CHILD_STATUS.success?
  else
    $stderr.puts(wget_out + "\n")
    raise 'Failed in getting the latest dump file'
  end
  if filename[/\.zip$/]
    unzip_out = `unzip -p data/#{filename} > data/#{filename.sub('.zip', '.csv')}`
    if $CHILD_STATUS.success?
    else
      $stderr.puts(unzip_out + "\n")
      raise 'Failed in unzipping the latest dump file'
    end
  end
  if File.zero?("data/#{filename}")
    raise 'Unexpected zero length csv file got exrtacted'
  end
  "data/#{filename.sub('.zip', '.csv')}"
end
