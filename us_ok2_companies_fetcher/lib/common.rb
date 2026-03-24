INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,', '*', "**", "***", "`"].freeze
EXCLUDE_CORP_TYPES = ["1","2","3","4","5", "6"]
PREFIXES = ["01","02","03","04","05","07","17"]
NAME_TYPE_ID_MAPPING = { "2" => "alias", "3" => "trading", "4" => "legal"}
DATA_ARRAY_LIMIT = 100000
MAIN_URL = "https://www.sos.ok.gov"
FILING_TYPE = []

TABLE_NAMES = {
  "01" => "ENTITY_INFORMATION",
  "02" => "ENTITY_ADDRESS_INFORMATION",
  "03" => "AGENT_INFORMATION",
  "04" => "OFFICER_INFORMATION",
  "05" => "NAMES_INFORMATION",
  "06" => "ASSOCIATED_ENTITIES",
  "07" => "STOCK_DATA",
  "08" => "STOCK_INFO",
  "09" => "STOCK_TYPE",
  "10" => "FILING_TYPE",
  "11" => "CORP_STATUS",
  "12" => "CORP_TYPE",
  "13" => "NAME_STATUS",
  "14" => "NAME_TYPE",
  "15" => "CAPACITY",
  "16" => "SUFFIX",
  "17" => "CORP_FILING",
  "18" => "AUDIT_LOG",
  "99" => "TRAILER_RECORD"
}

CSV.foreach("lib/mapping_files/FILING_TYPE_ID.csv", headers: true) do |row|
  FILING_TYPE << row.to_hash
end

STATUS_ID = {
  "1" => "In Existence",
  "2" => "Report Notice Sent",
  "3" => "RA Notice Sent",
  "4" => "Dissolved",
  "5" => "Judicially Dissolved",
  "7" => "Expired",
  "8" => "Withdrawn",
  "9" => "Merged",
  "10" => "Converted",
  "11" => "Consolidated",
  "12" => "Vol. Cancelled",
  "14" => "Deleted",
  "15" => "Past Due Report",
  "16" => "Impending Ouster",
  "18" => "OTC Suspension",
  "19" => "Cancelled",
  "20" => "Inactive",
  "21" => "Ousted",
  "22" => "Terminated",
  "23" => "Transferred"
}

CORP_TYPE_ID = {
  "1" => "Name Reservation",
  "2" => "LLC Name Reservation",
  "3" => "Domestic Trade Name Entity",
  "4" => "Foreign Trade Name Entity",
  "5" => "Domestic Partnership Fictitious Name Entity",
  "6" => "Foreign Partnership Fictitious Name Entity",
  "7" => "Domestic For Profit Business Corporation",
  "8" => "Domestic For Profit Corporation Professional",
  "9" => "Domestic For Profit Corporation Farm/Ranch",
  "10" => "Domestic For Profit Corporation Insurance",
  "12" => "Domestic For Profit Corporation Engineering and/or Architect",
  "13" => "Foreign For Profit Business Corporation",
  "14" => "Foreign For Profit Corporation Insurance",
  "15" => "Foreign For Profit Corporation Engineering and/or Architect",
  "16" => "Domestic Not For Profit Corporation",
  "17" => "Domestic Not For Profit Corporation Church",
  "18" => "Foreign Not For Profit Corporation",
  "19" => "Domestic Limited Liability Company",
  "20" => "Domestic Limited Liability Company Professional",
  "21" => "Domestic Limited Liability Company Insurance",
  "22" => "Domestic Limited Liability Company Engineering and/or Architect",
  "23" => "Foreign Limited Liability Company",
  "24" => "Foreign Limited Liability Company Insurance",
  "25" => "Foreign Limited Liability Company Engineering and/or Architect",
  "26" => "Domestic Limited Partnership",
  "27" => "Domestic Limited Partnership Professional",
  "28" => "Domestic Limited Partnership Insurance",
  "29" => "Domestic Limited Partnership Engineering and/or Architect",
  "30" => "Foreign Limited Partnership",
  "31" => "Foreign Limited Partnership Insurance",
  "32" => "Foreign Limited Partnership Engineering and/or Architect",
  "33" => "Domestic Limited Liability Partnership",
  "34" => "Foreign Limited Liability Partnership",
  "35" => "Domestic Religious Association",
  "36" => "Domestic Religious Association Church",
  "37" => "Domestic Bank",
  "38" => "Domestic Credit Union",
  "39" => "Domestic Savings & Loan",
  "40" => "Domestic Rail Road Corporation",
  "41" => "Domestic For Profit Cooperative",
  "42" => "Domestic Not For Profit Cooperative",
  "43" => "Foreign Not For Profit Cooperative",
  "44" => "Charitable Organization",
  "45" => "Professional Fund Raiser",
  "46" => "Athlete Agent",
  "47" => "Cities and Towns",
  "48" => "Public Trust",
  "49" => "Conservation District",
  "50" => "Professional Solicitor",
  "52" => "Partnership",
  "53" => "Foreign For Profit Corporation Professional",
  "54" => "Foreign Limited Liability Company Professional",
  "55" => "Foreign Limited Partnership Professional",
  "99" => "Other Entity"
}

STOCK_TYPE_ID = {
  "1" => "Common (Voting)",
  "2" => "Preferred (Voting)",
  "3" => "Preferred (Non-Voting)",
  "4" => "Cumulative Preferred (Voting)",
  "5" => "Cumulative Preferred (Non-Voting)",
  "6" => "Treasure Stock",
  "7" => "Convertible Preferred (Voting)",
  "8" => "Convertible Preferred (Non-Voting)",
  "9" => "Preference",
  "10" => "Common (Non-Voting)",
  "11" => "Common Cumulative Convertible",
  "12" => "Preferred Cumulative Convertible",
  "13" => "Unlimited Number of Shares",
  "14" => "Foreign Currency",
  "15" => "Undesignated Shares"
}

def clean_address(address)
  if address.key?(:street_address) || address.key?(:postal_code) || (address.key?(:locality) && address.key?(:country))
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
