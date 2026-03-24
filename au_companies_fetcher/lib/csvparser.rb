# encoding: iso-8859-1
require 'csv'
require 'openc_bot/helpers/dates'
require_relative 'common'

class CSVParser
  include OpencBot::Helpers::Dates
  attr_accessor :entry

  def initialize(input)
    @entry = input
  end

  def encapsulate_as_per_schema
    row = CSV.parse_line(entry[:entry], col_sep: "\t", quote_char: "\x00").to_a
    raise "Invalid line/row #{line} // #{row} was expecting #{entry[:headers].length}, but found #{row.length}" if row.length != entry[:headers].length && row.length != 12
    raw_data = Hash[entry[:headers].zip(row.strip)]
    return if raw_data['Company Name'] == 'Name'
    datum = {}
    datum[:name] = raw_data['Current Name'].blank? ? raw_data['Company Name'] : raw_data['Current Name']
    unless raw_data['Current Name'].blank?
      datum[:previous_names] = [
        {
          company_name: raw_data['Company Name'],
          con_date: (raw_data['Current Name Start Date'].blank? ? nil : Date.strptime(raw_data['Current Name Start Date'], '%d/%m/%Y'))
        }.reject {|_k, v| v.blank? }
      ]
    end
    datum[:company_number] = raw_data['ACN']
    company_type = case raw_data['Type']
                   when 'APTY'
                     'Australian Proprietary Company'
                   when 'APUB'
                     'Australian Public Company'
                   when 'ASSN'
                     'Association'
                   when 'BUSN'
                     'Business Name'
                   when 'CHAR'
                     'Charity'
                   when 'COMP'
                     'Community Purpose'
                   when 'COOP'
                     'Co-Operative Society'
                   when 'FNOS'
                     'Foreign Company (Overseas)'
                   when 'LTDP'
                     'Limited Partnership'
                   when 'MISM'
                     'Managed Investment Scheme'
                   when 'NONC'
                     'Non Company'
                   when 'NRET'
                     'Non Registered Entity'
                   when 'RACN'
                     'Registered Australian Body'
                   when 'REBD'
                     'Religious Body'
                   when 'RSVN', 'RSVD'
                     'Name Reservation'
                   when 'SOLS'
                     'Solicitor Corporation'
                   when 'TRST'
                     'Trust'
                   else
                     raise "Unhandle company_type: #{raw_data['Type'].dump} for #{datum}"
                   end
    datum[:branch] = case company_type
                     when /foreign/i
                       'F'
                     end

    company_class = case raw_data['Class']
                    when 'EQUT'
                      'Equity'
                    when 'LMGT'
                      'Limited By Guarantee'
                    when 'LMSG'
                      'Limited By Shares & Guarantee'
                    when 'LMSH'
                      'Limited By Shares'
                    when 'MORT'
                      'Mortgage'
                    when 'NLIA'
                      'No Liability'
                    when 'NONE'
                      nil # 'Does Not Have An Equivalent Australian Liability'
                    when 'PROP'
                      'Property'
                    when 'UNKN'
                      'Liability Unknown'
                    when 'UNLM'
                      'Unlimited'
                    when '', nil
                    else
                      raise "Unhandle company_class: #{raw_data['Class']} for #{datum} || #{raw_datum}"
                    end
    datum[:company_type] = [company_type, company_class].reject(&:blank?).join(', ').strip
    datum[:current_status] = case raw_data['Status']
                             when 'APPR'
                               'Approved (Trust)'
                             when 'ARCH'
                               'Business Names - Archived'
                             when 'ASOS'
                               'Association Strike Off Status'
                             when 'CNCL'
                               'Cancelled'
                             when 'CONV'
                               'Converted (Trust)'
                             when 'DISS'
                               'Dissolved By Special Act Of Parliament'
                             when 'DIV3'
                               'Organisation Transferred Registration Via Div3'
                             when 'DMNT'
                               'Dormant'
                             when 'DRGD'
                               'Deregistered'
                             when 'EXAA'
                               'External Administration - Associations'
                             when 'EXAD'
                               'Externally Administered'
                             when 'NOAC'
                               'Not Active'
                             when 'NRGD'
                               'Not Registered'
                             when 'PEND'
                               'Pending - Schemes'
                             when 'PROV'
                               'Provisional'
                             when 'REGD'
                               'Registered'
                             when 'REXP'
                               'Business Name Expired'
                             when 'RMVD'
                               'Business Names - Removed'
                             when 'SOFF'
                               'Strike-Off Action In Progress'
                             when 'WDUP'
                               'Winding Up - Managed Investments Schemes'
                             when 'WDPI'
                               'Winding Up - Prescribed Interest Schemes'
                             when 'RSVD'
                               'Reserved name'
                             when 'APPD'
                               'Approved name reservation'
                             else
                               raise "Unhandled current_status: #{raw_data['Status']} for #{datum} || #{raw_datum}"
                             end
    datum[:incorporation_date] = Date.strptime(raw_data['Date of Registration'].split(/\s/).first.strip, '%d/%m/%Y').iso8601 unless raw_data['Date of Registration'].blank?
    begin
      begin
        datum[:all_attributes] = {}
        #datum[:all_attributes][:business_number] = raw_data['ABN']
        datum[:identifiers] = [{uid: raw['ABN'], identifier_system_code: 'au_bn'}]
      end unless raw_data['ABN'] == '00000000000'
    end unless raw_data['ABN'].blank?
    datum[:retrieved_at] = entry[:published_date]
    datum[:jurisdiction_code] = 'au'
    datum
  end
end
