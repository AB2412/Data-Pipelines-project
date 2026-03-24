INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,', '[Not Provided]', ' [Not Provided]'].freeze
INDUSTRY_CODES_2022 = (OpencIndustryCodes::CodeScheme.find("us_naics_2022")).codes.map{|e| e.code}
INDUSTRY_CODES_2017 = (OpencIndustryCodes::CodeScheme.find("us_naics_2017")).codes.map{|e| e.code}
INDUSTRY_CODES_2012 = (OpencIndustryCodes::CodeScheme.find("us_naics_2012")).codes.map{|e| e.code}
INDUSTRY_CODES_2007 = (OpencIndustryCodes::CodeScheme.find("us_naics_2007")).codes.map{|e| e.code}
HEADER = {
  'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3',
  'User-Agent'=> 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
}
DATA_SOURCE = 'https://www.appmybizaccount.gov.on.ca/onbis/master/entry.pub?applicationCode=onbis-master&businessService=registerItemSearch'
MAIN_URL = 'https://www.appmybizaccount.gov.on.ca/onbis/master/viewInstance/view.pub'
COMPANY_TYPES = ['Partnerships', 'Corporations']
COMPANY_TYPES_SEARCH = {'Partnerships' => 'onbis-partnerships', 'Corporations' => 'onbis-corporations'}
MAX_THREAD = 2
QUEUE_PENDING_LIMIT = 10000
QUEUE_PROCESS_LIMIT = 20000
PROCESS_RUNTIME_LIMIT = 72000
RECORDS_PER_THREAD = 100
ACTIVE_STATUS_STALE_DAYS = 14
INACTIVE_STATUS_STALE_DAYS = 365
DAYS_GAP = 14
MONTHLY_GAP = 30
ACTIVE_STATUS_STALE_COUNT = 5000
INACTIVE_STATUS_STALE_COUNT = 1000
GAPS_RANGE = 1000
INITIAL_GAP_UID = 1000000000

def working_data_folder
  folders = Dir.glob("#{data_dir}/*").select {|f| (File.directory? f) && (f.include? '_processing')}
  folders.first
end

def rename_working_data_folder
  wkfd = working_data_folder
  new_path = working_data_folder.gsub('_processing', '')
  File.rename(wkfd, new_path)
end

def clean_address(address)
  if address.key?(:street_address) || address.key?(:postal_code) || (address.key?(:locality) && address.key?(:country))
    address
  else
    tmp = address.values.snap.join(', ')
    (tmp.size <= 3 ? nil : tmp)
  end
end

def validate_address(address)
  return false if address.blank?
  return false if address['locality'].blank? || address['country'].blank?
  true
end

def get_scheme_code(code)
  return nil if code.match?(/^9+$/)
  return 'us_naics_2022' if INDUSTRY_CODES_2022.include?(code)
  return 'us_naics_2017' if INDUSTRY_CODES_2017.include?(code)
  return 'us_naics_2012' if INDUSTRY_CODES_2012.include?(code)
  return 'us_naics_2007' if INDUSTRY_CODES_2007.include?(code)
end

class Hash
  def snap
    delete_if { |_k, v| INVALID_FIELDS.include?(v) }
  end
end

class Array
  def snap
    delete_if { |v| INVALID_FIELDS.include?(v) }
  end
end
