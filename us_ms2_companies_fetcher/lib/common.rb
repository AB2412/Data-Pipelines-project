INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,', 'NULL'].freeze
INDUSTRY_CODES_2022 = (OpencIndustryCodes::CodeScheme.find("us_naics_2022")).codes.map{|e| e.code}
INDUSTRY_CODES_2017 = (OpencIndustryCodes::CodeScheme.find("us_naics_2017")).codes.map{|e| e.code}
INDUSTRY_CODES_2012 = (OpencIndustryCodes::CodeScheme.find("us_naics_2012")).codes.map{|e| e.code}
INDUSTRY_CODES_2007 = (OpencIndustryCodes::CodeScheme.find("us_naics_2007")).codes.map{|e| e.code}

CURRENT_STATUS = {
  "Good" => "Good Standing",
  "IntentToDissolveAnnualReport" => "Intent To Dissolve - Failure to File Annual Report",
  "Cancelled" => "Canceled",
  "IntentToDissolveTax" => "Intent To Dissolve - Tax",
  "IntentToDissolveAnnualReport_RegisteredAgent" => "Intent To Dissolve - Failure to File Annual Report and no Registered Agent",
  "IntentToDissolveRegisteredAgent" => "Intent To Dissolve - No Registered Agent",
  "InActive" => "Inactive"
}

def clean_address(address)
  if (address.key?(:street_address) && (!address[:street_address].blank?)) || (address.key?(:postal_code) && !address[:postal_code].blank?) || ((address.key?(:locality) && !address[:locality].blank? ) && (address.key?(:country) && !address[:country].blank?))
    address
  elsif (!address[:country].blank?) && (address[:locality].blank?)
    nil
  else
    tmp = address.values.snap.join(', ')
    (tmp.size <= 3 ? nil : tmp)
  end
end

def get_scheme_code(code)
  return nil if code.match?(/^9+$/)
  return 'us_naics_2022' if INDUSTRY_CODES_2022.include?(code)
  return 'us_naics_2017' if INDUSTRY_CODES_2017.include?(code)
  return 'us_naics_2012' if INDUSTRY_CODES_2012.include?(code)
  return 'us_naics_2007' if INDUSTRY_CODES_2007.include?(code)
  'us_naics_2022'
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
