INVALID_FIELDS = [nil, '', ' ', '. .', '-', ", ", "??", {}, [], '00000', '0000', "00", '.', ',,'].freeze
INDUSTRY_CODES_2022 = (OpencIndustryCodes::CodeScheme.find("us_naics_2022")).codes.map{|e| e.code}
INDUSTRY_CODES_2017 = (OpencIndustryCodes::CodeScheme.find("us_naics_2017")).codes.map{|e| e.code}
INDUSTRY_CODES_2012 = (OpencIndustryCodes::CodeScheme.find("us_naics_2012")).codes.map{|e| e.code}
INDUSTRY_CODES_2007 = (OpencIndustryCodes::CodeScheme.find("us_naics_2007")).codes.map{|e| e.code}
INVALID_ADDRESS = ["****", "0", "RFD", "UNKNOWN", "NO ADDRESS LISTED", "(NO ADDRESS LISTED)", "(NO ADDRESS" "NO DIRECTORS NEED", "NOT LISTED", "NOT APPLICABLE", "NO CURRENT UTAH ADDRESS", "NA", "NONE ON FILE", "NONE ON FI", "NOT ON FILE", "NOT ON FI", "NONE", "N RECORD", "NO RECO", "NO RECORD", "NO ADDRESS GIVEN", "NONE LISTED"]
INVALID_OFFICERS = ["***", "No Director per Statute UCA \u0026sect 16-10a-732", "No Director per Statute UCA Sect 16-10a-732", "NOT LISTED", "NO ADDRES", "NO DIR", "NO DIRECTOR", "NO STREET", "NOT AVAILABLE", "NOT APPLICABLE", "NO OFFICER", "no dir", "no officer", "*** ***", "NO AGENT, REFER TO UCA ?16-17-301", "no agent, refer to uca §16-17-301", "none on fle", "no director per statute uca sect16-10A-732", "AGENT REMOVE", "AGENT RESIGN", "AGENT RESIFN", "AGENT RERSIGN", "AGENT RESIGTN", "AGENT RESSIGNED", "AGENT RESINGED", "AGENT RESGNED", "AGENT RESGINED", "AGENT REISGNED", "AGENT REDIGNED", "AGENT DELETED", "AGENT REMOVED", "AGENT RESIFNED", "AGENT RERSIGNED", "AGENT RESIGNES", "AGENT RESIGNS", "AGENT RESIGNED", "AGENTS REMOVE", "AGENTS RESIGN", "AGENTS RESIFN", "AGENTS RERSIGN", "AGENTS RESIGTN", "AGENTS RESSIGNED", "AGENTS RESINGED", "AGENTS RESGNED", "AGENTS RESGINED", "AGENTS REISGNED", "AGENTS REDIGNED", "AGENTS DELETED", "AGENTS REMOVED", "AGENTS RESIFNED", "AGENTS RERSIGNED", "AGENTS RESIGNES", "AGENTS RESIGNS", "AGENTS RESIGNED", "OFFICER REMOVE", "OFFICER RESIGN", "OFFICER RESIFN", "OFFICER RERSIGN", "OFFICER RESIGTN", "OFFICER RESSIGNED", "OFFICER RESINGED", "OFFICER RESGNED", "OFFICER RESGINED", "OFFICER REISGNED", "OFFICER REDIGNED", "OFFICER DELETED", "OFFICER REMOVED", "OFFICER RESIFNED", "OFFICER RERSIGNED", "OFFICER RESIGNES", "OFFICER RESIGNS", "OFFICER RESIGNED", "OFFICERS REMOVE", "OFFICERS RESIGN", "OFFICERS RESIFN", "OFFICERS RERSIGN", "OFFICERS RESIGTN", "OFFICERS RESSIGNED", "OFFICERS RESINGED", "OFFICERS RESGNED", "OFFICERS RESGINED", "OFFICERS REISGNED", "OFFICERS REDIGNED", "OFFICERS DELETED", "OFFICERS REMOVED", "OFFICERS RESIFNED", "OFFICERS RERSIGNED", "OFFICERS RESIGNES", "OFFICERS RESIGNS", "OFFICERS RESIGNED", "DIRECTO REMOVE", "DIRECTO RESIGN", "DIRECTO RESIFN", "DIRECTO RERSIGN", "DIRECTO RESIGTN", "DIRECTO RESSIGNED", "DIRECTO RESINGED", "DIRECTO RESGNED", "DIRECTO RESGINED", "DIRECTO REISGNED", "DIRECTO REDIGNED", "DIRECTO DELETED", "DIRECTO REMOVED", "DIRECTO RESIFNED", "DIRECTO RERSIGNED", "DIRECTO RESIGNES", "DIRECTO RESIGNS", "DIRECTO RESIGNED", "DIRECTR REMOVE", "DIRECTR RESIGN", "DIRECTR RESIFN", "DIRECTR RERSIGN", "DIRECTR RESIGTN", "DIRECTR RESSIGNED", "DIRECTR RESINGED", "DIRECTR RESGNED", "DIRECTR RESGINED", "DIRECTR REISGNED", "DIRECTR REDIGNED", "DIRECTR DELETED", "DIRECTR REMOVED", "DIRECTR RESIFNED", "DIRECTR RERSIGNED", "DIRECTR RESIGNES", "DIRECTR RESIGNS", "DIRECTR RESIGNED", "DIREECTOR REMOVE", "DIREECTOR RESIGN", "DIREECTOR RESIFN", "DIREECTOR RERSIGN", "DIREECTOR RESIGTN", "DIREECTOR RESSIGNED", "DIREECTOR RESINGED", "DIREECTOR RESGNED", "DIREECTOR RESGINED", "DIREECTOR REISGNED", "DIREECTOR REDIGNED", "DIREECTOR DELETED", "DIREECTOR REMOVED", "DIREECTOR RESIFNED", "DIREECTOR RERSIGNED", "DIREECTOR RESIGNES", "DIREECTOR RESIGNS", "DIREECTOR RESIGNED", "DIRESTOR REMOVE", "DIRESTOR RESIGN", "DIRESTOR RESIFN", "DIRESTOR RERSIGN", "DIRESTOR RESIGTN", "DIRESTOR RESSIGNED", "DIRESTOR RESINGED", "DIRESTOR RESGNED", "DIRESTOR RESGINED", "DIRESTOR REISGNED", "DIRESTOR REDIGNED", "DIRESTOR DELETED", "DIRESTOR REMOVED", "DIRESTOR RESIFNED", "DIRESTOR RERSIGNED", "DIRESTOR RESIGNES", "DIRESTOR RESIGNS", "DIRESTOR RESIGNED", "DIRETOR REMOVE", "DIRETOR RESIGN", "DIRETOR RESIFN", "DIRETOR RERSIGN", "DIRETOR RESIGTN", "DIRETOR RESSIGNED", "DIRETOR RESINGED", "DIRETOR RESGNED", "DIRETOR RESGINED", "DIRETOR REISGNED", "DIRETOR REDIGNED", "DIRETOR DELETED", "DIRETOR REMOVED", "DIRETOR RESIFNED", "DIRETOR RERSIGNED", "DIRETOR RESIGNES", "DIRETOR RESIGNS", "DIRETOR RESIGNED", "DIRECTOR REMOVE", "DIRECTOR RESIGN", "DIRECTOR RESIFN", "DIRECTOR RERSIGN", "DIRECTOR RESIGTN", "DIRECTOR RESSIGNED", "DIRECTOR RESINGED", "DIRECTOR RESGNED", "DIRECTOR RESGINED", "DIRECTOR REISGNED", "DIRECTOR REDIGNED", "DIRECTOR DELETED", "DIRECTOR REMOVED", "DIRECTOR RESIFNED", "DIRECTOR RERSIGNED", "DIRECTOR RESIGNES", "DIRECTOR RESIGNS", "DIRECTOR RESIGNED", "DIRECTORS REMOVE", "DIRECTORS RESIGN", "DIRECTORS RESIFN", "DIRECTORS RERSIGN", "DIRECTORS RESIGTN", "DIRECTORS RESSIGNED", "DIRECTORS RESINGED", "DIRECTORS RESGNED", "DIRECTORS RESGINED", "DIRECTORS REISGNED", "DIRECTORS REDIGNED", "DIRECTORS DELETED", "DIRECTORS REMOVED", "DIRECTORS RESIFNED", "DIRECTORS RERSIGNED", "DIRECTORS RESIGNES", "DIRECTORS RESIGNS", "DIRECTORS RESIGNED", "PRES/ AGENT REMOVE", "PRES/ AGENT RESIGN", "PRES/ AGENT RESIFN", "PRES/ AGENT RERSIGN", "PRES/ AGENT RESIGTN", "PRES/ AGENT RESSIGNED", "PRES/ AGENT RESINGED", "PRES/ AGENT RESGNED", "PRES/ AGENTRESGINED", "PRES/ AGENT REISGNED", "PRES/ AGENT REDIGNED", "PRES/ AGENT DELETED", "PRES/ AGENT REMOVED", "PRES/ AGENT RESIFNED", "PRES/ AGENT RERSIGNED", "PRES/ AGENT RESIGNES", "PRES/ AGENT RESIGNS", "PRES/ AGENT RESIGNED","\\\\"]
VALID_OFFICER_NAME_REGEX = /[a-zA-Z]+/
ALLOWED_OFFICER_TITLES = ["Individual", "Entity", "DOPL - Officer", "Chairman of the Board", "Owner", "Former Registered Agent", "Authorized Member", "Former Director", "Former Secretary", "Managing Member", "Other", "Chief Executive Officer", "Former Trustee", "Former Partner", "Former Administrator", "Chief Operating Officer", "Chief Financial Officer", "Applicant", "Assistant Director", "Assistant Secretary", "Asst. Sec.", "CCO", "CEO", "CFO", "CLO", "COO", "Contact Person", "Contractor Owner", "Controller", "DBA", "Director", "Governing Person", "Incorporator", "Joint Member", "Manager", "Member", "Officer", "Organizer", "PIC", "Parent Organization", "Parent Organization Contact", "Partner", "President", "Registered Agent", "Responsible Individual", "School Contact", "Secretary", "Sole Owner", "Supervisor", "Treasurer", "Trustee", "Vice President", "agent"]
REGISTERED_ADDRESS_SCHEMA = [
  ['Address', 'Address 2'],
  'City',
  ['State'],
  ['Zip Code']
]

def parse_address(address)
  if address.nil?
    return false
  else
    if address.is_a?(String)
      return false
    else
      address['street_address'] = " " if !address.key?('street_address')
      return address
    end
  end
end

def clean_address(address)
  address = address.snap
  address.delete_if { |_, v| INVALID_ADDRESS.any? {|invalid| v.downcase.start_with?(invalid.downcase)} || INVALID_OFFICERS.any? {|invalid| v.to_s.downcase.start_with?(invalid.downcase)} }
  if address.key?('street_address') || address.key?('postal_code') || (address.key?('locality') && address.key?('country'))
    address.each { |k, v| address[k] = v.strip if v.is_a?(String) }
  else
    nil
  end
end

def normalise_date(str)
  return nil if str.blank?
  date = Date.strptime(str, '%Y-%m-%d') rescue nil
  return nil unless date

  # Adjust the year if it is in the future (assuming dates should be in the past)
  if date.year > Date.today.year
    date = date.prev_year(100)
  end

  date.strftime('%Y-%m-%d')
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
