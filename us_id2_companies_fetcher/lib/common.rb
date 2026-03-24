INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,', 'n/a', 'NO AGENT', '*****', 'NA', 'N/A', 'SAME', 'NONE', 'NONE LISTED', 'NONELISTED'].freeze
EXCLUDE_COMPANY_TYPES = ['Foreign Name Registration', 'Reservation of Legal Entity Name', 'Assumed Business Name'].freeze
BAD_ADDRESS = ['0', 'Other']

FILING_DATUM_ATTRIBUTES = {
  'CONTROL_NO' => 'company_number',
  'FILING_TYPE' => 'company_type',
  'STATUS' => 'current_status',
  'FILING_NAME' => 'name',
  'FILING_DATE' => 'incorporation_date',
  'INACTIVE_DATE' =>'dissolution_date',
}

FILING_ALL_ATTRIBUTES = {
  'DURATION_TYPE' => 'Term of Duration',
  'STANDING-AR' => 'STANDING-AR',
  'STANDING-RA' => 'STANDING-RA',
  'STANDING-OTHER' => 'STANDING-OTHER',
  'DELAYED_EFFECTIVE_DATE' => 'Delayed Effective Date',
  'EXPIRATION_DATE' => 'expiration_date',
  'FORMATION_LOCALE' => 'State of Origin',
  'FORM_HOME_JURIS_DATE' => 'home_incorporation_date',
  'AR_EXEMPT_YN' => 'AR_EXEMPT_YN',
  'PUBLIC_BENEFIT_YN' => 'PUBLIC_BENEFIT_YN',
  'AR_DUE_DATE' => 'AR Due Date'
}

REGISTERED_ADDRESS = [
  ['PRINCIPLE_ADDR1', 'PRINCIPLE_ADDR2', 'PRINCIPLE_ADDR3'],
  ['PRINCIPLE_CITY'],
  'PRINCIPLE_STATE',
  'PRINCIPLE_POSTAL_CODE',
  'PRINCIPLE_COUNTRY'
]

MAILING_ADDRESS = [
  ['MAIL_ADDR1', 'MAIL_ADDR2', 'MAIL_ADDR3'],
  ['MAIL_CITY'],
  'MAIL_STATE',
  'MAIL_POSTAL_CODE',
  'MAIL_COUNTRY'
]

OFFICER_ADDRESS = [
  ['ADDR1', 'ADDR2', 'ADDR3'],
  ['CITY', 'COUNTY'],
  'STATE',
  'POSTAL_CODE',
  'COUNTRY'
]

def date_format(value)
  return if value.blank?
  date = Date.strptime(value, "%m/%d/%Y") rescue nil
  return if (!date) || (date.year < 1800)
  date.to_s
end

def object_date_format(obj, keys)
  keys.each do |key|
    obj[key] = date_format(obj[key])
  end
end

def clean_address(address)
  address.each do |key, value|
    if value.strip.match?(/^[-*]+$/) || BAD_ADDRESS.include?(value)
      address[key] = nil
    end
  end
  address.snap
  if address.key?('street_address') || address.key?('postal_code') || (address.key?('locality') && address.key?('country'))
    address
  else
    tmp = address.values.snap.join(', ')
    (tmp.size <= 3 ? nil : tmp)
  end
end

def strip_values(hash)
  hash.each do |key, value|
    if value.is_a?(Hash)
      strip_values(value)
    elsif value.is_a?(Array)
      value.each { |v| strip_values(v) if v.is_a?(Hash) }
    elsif value.is_a?(String)
      hash[key] = value.strip
    end
  end
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
