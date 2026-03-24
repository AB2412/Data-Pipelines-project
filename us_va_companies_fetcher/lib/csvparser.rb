module UsVaCompaniesFetcher
  class CSVParser
    include OpencBot::Helpers::RegisterMethods
    def initialize(input)
      input.each do |key, value|
        self.class.__send__(:attr_accessor, key)
        __send__("#{key}=", value)
      end
    end

    def encapsulate_as_per_schema
      datum = {
        jurisdiction_code: 'us_va',
        retrieved_at: retrieved_at,
        all_attributes: {},
        company_type: company_type,
        total_shares: {},
        officers: [],
        previous_names: [],
        alternative_names: [],
        filings: []
      }
      address = {}
      agent = { position: 'agent', other_attributes: { address: {} } }
      company.snap.each do |key, value|
        case key
        when 'EntityID'
          datum[:company_number] = value
          if value[/^F|^M|^T/]
            datum[:company_type] = ['Foreign', datum[:company_type]].join(' ').strip
            datum[:branch] = 'F'
          end
        when 'Name'
          value = value.gsub(/\s{1,}/, ' ').strip
          if value['USED IN VA']
            tmp = extract_names(value) rescue nil
            if tmp.blank?
              datum[:name] = value
            elsif tmp.size != 2
              raise "Unhandled case of multiple names: #{tmp}"
            else
              datum[:alternative_names] << { company_name: tmp[1], type: 'legal' }
              datum[:name] = tmp[0]
            end
          else
            datum[:name] = value
          end
        when 'Status'
          datum[:current_status] = value
        when 'StatusReason'
          datum[:all_attributes][:status_reason] = value
        when 'Status Date'
          tmp = normalise_date(value)
          datum[:all_attributes]['StatusDate'] = tmp
          datum[:dissolution_date] = case datum[:current_status]
                                     when 'INACTIVE'
                                       tmp
                                     when 'ACTIVE'
                                       # noop
                                     when 'PENDACT', 'PENDINACT'
                                       # noop
                                     else
                                       raise "Unhandled case of dissolution_date: \n#{JSON.pretty_generate(datum)}"
                                     end
        when 'Duration', 'PrinOffEffDate', 'MergerInd', 'AssessInd', 'StockInd', 'Is Series LLC', 'Is Protected Series',
             'Series LLC ID'
          datum[:all_attributes][key] = value
        when 'IncorpDate'
          datum[:incorporation_date] = normalise_date(value)
        when 'IncorpState'
          datum[:all_attributes][:jurisdiction_of_origin] = value
        when 'IndustryCode'
          datum[:all_attributes][:business_classification_text] = LOOKUP[['IndustryCode', format('%02d', value.split('-').first.strip)]]
        when 'Street1'
          address[:street_address] = value
        when 'Street2'
          address[:street_address] = [address[:street_address], value].reject(&:blank?).join(', ')
        when 'City'
          address[:locality] = value
        when 'State'
          address[:region] = value
        when 'Zip'
          address[:postal_code] = ([nil, '', '00000'].include?(value) ? nil : value)
        when 'RA-Name'
          agent[:name] = value.gsub(/\s{1,}/, ' ').strip
        when 'RA-Street1'
          agent[:other_attributes][:address][:street_address] = value
        when 'RA-Street2'
          agent[:other_attributes][:address][:street_address] = [address[:street_address], value].reject(&:blank?).join(', ')
        when 'RA-City'
          agent[:other_attributes][:address][:locality] = value
        when 'RA-State'
          agent[:other_attributes][:address][:region] = value
        when 'RA-Zip'
          agent[:other_attributes][:address][:postal_code] = value
        when 'RA-EffDate'
          agent[:start_date] = normalise_date(value)
        when 'RA-Loc'
        when 'RA-Status'
          agent[:other_attributes]['status'] = value
        when 'TotalShares'
          tmp = value.gsub(',', '').to_i
          datum[:total_shares][:number] = ([nil, 0, '0'].include?(tmp) ? nil : tmp)
        when 'Stock1'
          datum[:total_shares][:share_class] = value
        else
          raise "Unhandled key-value pair: #{[key, value].to_json}"
        end
        company.delete(key)
      end

      name_history&.each do |entry|
        name = nil
        if entry['EntityName']['USED IN VA']
          tmp = extract_names(entry['EntityName']) rescue nil
          if tmp.blank?
            name = entry['EntityName']
          elsif tmp.size != 2
            raise "Unhandled case of multiple names: #{[entry['EntityName'], tmp].to_json}"
          else
            name = tmp[0]
            datum[:alternative_names] << { company_name: tmp[1], type: 'legal', start_date: (normalise_date(entry['NameEffDate']) rescue nil) }.snap
          end
        else
          name = entry['EntityName']
        end
        unless name.blank?
          if entry['NameStatus'] == '50'
            datum[:alternative_names] << { company_name: name, type: 'trading', start_date: (normalise_date(entry['NameEffDate']) rescue nil) }.snap
          else
            datum[:previous_names] << { company_name: name, start_date: (normalise_date(entry['NameEffDate']) rescue nil) }.snap
          end
        end
      end

      officer&.each do |entry|
        officer_titles = entry['OfficerTitle'].empty? ? [""] : entry['OfficerTitle'].gsub(' & ', ' / ').split('/').strip

        officer_titles.each do |position|
          name = [entry['OfficerFirstName'], entry['OfficerMiddleName'], entry['OfficerLastName']].reject(&:blank?).join(' ').force_encoding('utf-8')
          next if name.blank?

          next if name[/#{INVALID_OFFICER_REGEX}/]

          datum[:officers] << {
            name: name,
            position: position
          }.snap
        end
      end

      merger_info = merger&.select { |entry| entry['MergerType'] == 'N' }
      merger_info&.delete_if { |entry| entry['SurvivorID'].blank? && entry['ForeignName'].blank? }
      unless merger_info.blank?
        if merger_info.size == 1
          merger_info = merger_info.first
        else
          merger_info = merger_info.sort_by { |entry| entry['RA-EffDate'].blank? ? nil : Date.parse(entry['RA-EffDate']) }
          if merger_info.collect { |entry| entry['SurvivorID'] }.uniq.size == 1
            merger_info = merger_info.first
          else
            merger_type = merger_info.collect { |entry| entry['MergerType'] }.sort.uniq
            raise "Unhandled merger information: \n#{merger.to_json}" unless merger_type == ['N']

            merger_info = merger_info.last
          end
        end
        unless merger_info['SurvivorID'].blank? && merger_info['ForeignName'].blank?
          datum[:all_attributes][:merged_into] = {
            surviving_company: {
              company_number: merger_info['SurvivorID'],
              name: normalise_merger_name(merger_info['ForeignName'])[0],
              effective_date: normalise_date(merger_info['EffDate'])
            }.snap
          }
          datum[:all_attributes][:merged_into][:surviving_company].snap
        end
      end

      unless agent[:name].blank? || agent[:name][/#{INVALID_OFFICER_REGEX}/]
        agent[:other_attributes][:address] = clean_address(agent[:other_attributes][:address])
        agent[:other_attributes].snap
        datum[:officers] << agent
      end

      amendments&.each do |entry|
        filing = { description: [] }
        entry.each do |key, value|
          case key
          when 'EntityID'
            # noop
          when 'AmenDate'
            filing[:date] = normalise_date(value)
          when /AmenType/
            filing[:description] << value
          when 'Stock1'
          else
            raise "Unhandled key value pair in amendments: #{[key, value].to_json}"
          end
        end
        filing[:description] = filing[:description].snap.join(', ').strip
        datum[:filings] << filing if valid_filing?(filing)
      end

      datum[:total_shares] = nil if datum[:total_shares][:number].blank?
      datum[:registered_address] = clean_address(address.snap)
      datum[:all_attributes].snap

      defaults(datum.snap)
    end

    def normalise_merger_name(orig_name)
      name = orig_name.sub('NOT QUALIFIED IN VA', '').strip
      tmp = name.split('(').strip
      [tmp[0], tmp[1].to_s.scan(/^A ([A-Z]{2}) /).flatten.first]
    end

    def defaults(datum)
      datum[:branch] = nil if datum[:branch].blank?
      datum[:dissolution_date] = '' if datum[:dissolution_date].blank?
      datum
    end
  end
end
