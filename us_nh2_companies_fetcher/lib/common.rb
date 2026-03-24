INVALID_FIELDS = ['0', nil, [], {}, '', ' ', ',' ,'. .', '-', '.', '00000', '0000', '.', ',,', 'n/a', '&nbsp', 'Not on file', 'No address on file', 'Not Available', 'No Address', 'Unknown Address', 'Unknown', "Unknown\n", '[Address Not Available]', 'NONE', 'NOT-AVAILABLE', 'Not Required', 'N/A', 'none', 'Not Stated', 'Non Registered Business', 'DATA NOT FOUND'].freeze
BUSINESS_DETAIL = ["BusinessID", "BusinessName", "HomeStateName", "BusinessStatus", "BusinessType", "CreationDate", "DateInJurisdiction", "Duration", "ManagementStyle", "FiscalYearDate", "CitizenshipOrStateOfIncorporation", "LastBenefitReportYear", "NextBenefitReportYear", "LastAnnualReportYear", "NextAnnualReportYear", "BusinessEmail", "NotificationEmail", "PhoneNumber"]
BUSINESS_ADDRESS = ["BusinessID", "PrincipalOfficeStreetAddress", "PrincipalOfficeStreetAddress2", "PrincipalOfficeCity", "PrincipalOfficeState", "PrincipalOfficeZip", "PrincipalOfficeCounty", "PrincipalOfficeCountry", "MailingStreetAddress", "MailingStreetAddress2", "MailingCity", "MailingState", "MailingZip", "MailingCounty", "MailingCountry"]
FILING = ["BusinessID", "FilingDateTime", "EffectiveDate", "FilingType", "FilingNumber"]
PREVIOUS_BUSINESS_NAMES = ["BusinessID", "PreviousName", "PreviousNameType"]
PRINCIPAL_PURPOSE = ["BusinessID", "NAICSCODE", "NAICSSUBCODE"]
PRINCIPALS = ["BusinessID", "PrincipalName", "PrincipalTitle", "PrincipalStreetAddress", "PrincipalStreetAddress2", "PrincipalCity", "PrincipalState", "PrincipalZip", "PrincipalCounty", "PrincipalCountry"]
REGISTERED_AGENT = ["BusinessID", "RegisteredAgentName", "RegisteredAgentType", "PrincipalOfficeStreetAddress", "PrincipalOfficeStreetAddress2", "PrincipalOfficeCity", "PrincipalOfficeState", "PrincipalOfficeZip", "PrincipalOfficeCounty", "PrincipalOfficeCountry", "MailingStreetAddress", "MailingStreetAddress2", "MailingCity", "MailingState", "MailingZip", "MailingCounty", "MailingCountry"]
STOCK = ["BusinessID", "ShareClass", "NumberOfShares", "ParValue", "Note"]

REJECTED_STATUS = ['Hold','Rejected', 'Rejection Name Protected', 'Reserved Name', 'Reserved Name Cancelled', 'Reserved Name Expired']
REJECTED_COMPANY_TYPE = ['Correspondence', 'FORCED DBA', 'Foreign Registered Corporate Name', 'Non Registered', 'Trade Name']
FILING_TYPES =  ['Merger', 'Merged', 'Conversion', 'Withdraw/Dissolve/Cancel']
FILING_TYPE_TO_FILING_TITLE = {
  'Amendment' => 'Amend/Restate',
  'Merger' => 'Merged',
  'Trade Name Registration' => 'Tradename Registration',
  'Trade Name Withdrawal in Partnership' => 'Tradename Withdrawal in Partnership',
  'Trade Name Addition in Partnership' => 'Tradename Addition in Partnership'
}
BULK_COUNT = 10000

HOST = 'https://quickstart.sos.nh.gov'
IMAP_SERVER = 'imap.gmail.com'
IMAP_PORT = 993
IMAP_SSL = true
HEADER = {'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; rv:60.0) Gecko/20100101 Firefox/60.0', 'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', 'Connection' => 'keep-alive', 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8', 'Authority' => 'quickstart.sos.nh.gov', 'Origin' => 'https://quickstart.sos.nh.gov'}

def clean_address(address)
  if address.key?(:street_address) || address.key?(:postal_code) || (address.key?(:locality) && address.key?(:country))
    address.each do |key, value|
      cleaned_address = value.gsub(/,+$/, '').strip
      if cleaned_address.empty?
        address.delete(key)
      else
        address[key] = cleaned_address
      end
    end
    address
  else
    tmp = address.values.snap.join(', ')
    (tmp.size <= 3 ? nil : tmp)
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

def squish_values(obj)
  case obj
  when Hash
    obj.each_with_object({}) do |(key, value), new_hash|
      new_hash[key] = squish_values(value) # Recursively process hash values
    end
  when Array
    obj.map { |element| squish_values(element) } # Recursively process array elements
  when String
    obj.squish # Remove extra spaces from strings
  else
    obj # Return non-string, non-hash, non-array values as-is
  end
end
