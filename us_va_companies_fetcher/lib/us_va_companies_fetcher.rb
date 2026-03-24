require 'openc_bot'
require 'openc_bot/company_fetcher_bot'
require_relative 'csvparser'
require_relative 'common'
require_relative 'sqlite_wrapper'
require 'nokogiri'
require 'awesome_print'
require 'csv'
require 'openc_bot/helpers/dates'
require 'mechanize'
require 'hashdiff'
require 'retriable'

module UsVaCompaniesFetcher
  extend OpencBot
  extend OpencBot::CompanyFetcherBot
  extend OpencBot::Helpers::IncrementalSearch
  extend OpencBot::Helpers::Dates
  extend self # make these methods as Module methods, rather than instance ones

  RAISE_WHEN_SAVING_INVALID_RECORD = true
  SAVE_RAW_DATA_ON_FILESYSTEM = 1
  INVALID_OFFICER_REGEX = Regexp.compile('^[^[:alnum:]]+$').freeze
  LOOKUP = CSV.read('lib/lookup.csv', headers: true).map(&:to_hash).group_by { |row| row['ColumnID'] }.map { |key, row| row.map { |entry| { [key, entry['ColumnValue']] => entry['Description'] } } }.flatten.inject(&:update)
  CREDENTIALS = get_bot_secret("us_va")
  @added, @updated = 0, 0

  def update_data(options = {})
    result = fetch_data || {}
    result.update({ added: @added, updated: @updated })
    raise "\n#{JSON.pretty_generate(result)}" if result.key?(:fetch_data_error)

    result
  rescue StandardError => e
    send_error_report(e, options)
    raise e
  end

  def exception_to_json(exp)
    { 'klass' => exp.class.to_s, 'message' => exp.message, 'backtrace' => exp.backtrace }
  end

  def fetch_data
    if ENV['OPENDATA_FILE']
      db
      process_publish
    else
      log_info = proc do |exception, try, elapsed_time, next_interval|
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end
      Retriable.retriable tries: 10, base_interval: 120, on_retry: log_info do
        Mechanize.start do |tab|
          tab.verify_mode = OpenSSL::SSL::VERIFY_NONE
          tab.pluggable_parser.default = Mechanize::Download
          tab.keep_alive = false
          tab.max_history=0
          tab.set_proxy(CREDENTIALS["ZYTE_API_HOST"], CREDENTIALS["ZYTE_API_PORT"], CREDENTIALS["ZYTE_API_KEY"], '')
          url = 'https://cis.scc.virginia.gov/DataSales/DownloadBEDataSalesFile'
          resp = tab.head(url)
          filename = resp.header['content-disposition'].sub('attachment; filename=', '')
          warn "Found file with the name: #{filename}"
          raise "Unexpected filename: #{filename}" unless filename[/^BEData(.*)\.zip$/]

          outfile = "#{data_dir}/#{filename}"

          # Download the file
          unless File.exist?(outfile)
            warn "Downloading file: #{filename} to #{outfile}"
            tab.get(url, [], nil, { "zyte-file-download" => "true" } ).save!(outfile)
          end

          if get_var(filename).blank?
            outdir = unzip(outfile)
            db("#{outdir}/opendata.db")
            to_sqlite(outdir)
            process_publish
            save_var(filename, 'complete')
          else
            warn "Already processed the file: #{filename}"
          end
        end
      end

    end
    {}
  end

  def process_publish
    db.execute('CREATE INDEX idx0 on Corp(EntityID);') rescue nil
    db.execute('CREATE INDEX idx1 on LP(EntityID);') rescue nil
    db.execute('CREATE INDEX idx2 on LLC(EntityID);') rescue nil
    db.execute('CREATE INDEX idx3 on Officer(EntityID);') rescue nil
    db.execute('CREATE INDEX idx4 on NameHistory(EntityID);') rescue nil
    db.execute('CREATE INDEX idx5 on Amendment(EntityID);') rescue nil
    db.execute('CREATE INDEX idx6 on Merger(EntityID);') rescue nil
    db.execute('create table if not exists ocdump(EntityID, CompanyType)')
    if db.execute('select count(*) as cnt from ocdump').first['cnt'].zero?
      db.execute("insert into ocdump(EntityID, CompanyType) select EntityID, 'LLC' from LLC")
      db.execute("insert into ocdump(EntityID, CompanyType) select EntityID, 'LP' from LP")
      db.execute("insert into ocdump(EntityID, CompanyType) select EntityID, 'Corp' from Corp")
    end
    rowid = (get_var('del_rowid') || 0).to_i
    rs = db.query('select EntityID, CompanyType, rowid from ocdump where rowid>=? order by rowid asc', rowid)
    while (tuple = rs.next)
      update_datum([tuple['EntityID'], tuple['CompanyType']].reject(&:blank?).join('##'))
      save_var('del_rowid', tuple['rowid'].to_s)
    end
    save_var('del_rowid', nil)
  end

  def process_datum(input)
    datum = UsVaCompaniesFetcher::CSVParser.new(input).encapsulate_as_per_schema
    unless datum.blank?
      if (datum_exists?(datum[:company_number]) rescue false) == true
        @updated += 1
      else
        @added += 1
      end
    end
    datum
  end

  def fetch_datum(company_number, options = {})
    warn "Processing: #{company_number}"
    return opendata_fetch_datum(company_number, options) if company_number['##']

    _, company_type = get_company(company_number)
    return nil if company_type.nil?

    opendata_fetch_datum([company_number, company_type].join('##'), options)
  end

  def get_company(company_number, company_type = nil)
    if company_type.blank?
      company_type = if db.execute('select count(*) as cnt from Corp where EntityID=?', company_number).first['cnt'] != 0
                       'Corp'
                     elsif db.execute('select count(*) as cnt from LLC where EntityID=?', company_number).first['cnt'] != 0
                       'LLC'
                     elsif db.execute('select count(*) as cnt from LP where EntityID=?', company_number).first['cnt'] != 0
                       'LP'
                     else
                       warn "Unavailable company type: #{company_number}"
                       nil
                     end
    end
    return [nil, nil] if company_type.blank?

    tuple = db.execute("select * from #{company_type} where EntityID=?", company_number)
    company = if tuple.blank?
                nil
              elsif tuple.size > 1
                tuple = tuple.sort_by { |t| t['RA-EffDate'].blank? ? nil : Date.parse(t['RA-EffDate']) }
                diff = Hashdiff.diff(tuple[0], tuple[1])
                case diff.size
                when 1
                  case diff.first[1]
                  when 'RA-EffDate'
                    tuple.last
                  when 'MergerInd'
                    tuple.select { |t| t['MergerInd'] == 'N' }.first
                  else
                    ap tuple
                    ap diff
                    raise 'Case 1'
                  end
                else
                  ap tuple
                  ap diff
                  raise 'Case 2'
                end
              else
                tuple.last
              end
    [company, company_type]
  end

  def opendata_fetch_datum(transformed_company_number, _options = {})
    warn "Processing transformed company_number: #{transformed_company_number}"
    company_number, company_type = transformed_company_number.split('##').strip
    company, _tmp = get_company(company_number, company_type)
    input = {
      company_number: company_number,
      company: company,
      merger: (db.execute('select * from Merger where EntityID=?', company_number) rescue nil),
      amendments: db.execute('select * from Amendment where EntityID=?', company_number),
      name_history: db.execute('select * from NameHistory where EntityID=?', company_number),
      officer: db.execute('select * from Officer where EntityID=?', company_number),
      retrieved_at: @retrieved_at
    }
    input[:company_type] = case company_type
                           when 'Corp'
                             'Corporation'
                           when 'LLC'
                             'Limited Liability Company'
                           when 'LP'
                             'Limited Partnership'
                           else
                             raise "Unhandled company_type: #{company_type}"
                           end
    IO.write("#{data_dir}/details.json", JSON.pretty_generate(input))
    input[:company].blank? ? nil : input
  end

  def db(file = ENV['OPENDATA_FILE'])
    @retrieved_at ||= Time.strptime(file.split('/')[-2].sub('BEData', ''), '%m%d%Y').utc.iso8601
    @db ||= SQLite3::Database.new(file, results_as_hash: true)
  end

  def unzip(file_loc, dest = nil)
    dest ||= file_loc.to_s.sub(/.zip$/, '')
    return dest if Dir.exist?(dest)

    FileUtils.mkdir_p(dest)
    command = "unzip -uo #{file_loc} -d #{dest}  2>&1"
    warn "About to unzip #{file_loc} to #{dest}"
    output = `#{command}` # backticks capture the output, unlike system, which just returns true
    raise "problem unzipping file: #{output}" unless $CHILD_STATUS.success?

    warn output
    warn 'Successfully unzipped file'
    dest
  end

  def to_sqlite(dir)
    Dir.glob("#{dir}/*.csv") do |filename|
      warn "Processing: #{filename}"
      entries = []
      keys = nil
      tablename = filename.split('/').last.split('.').first
      if (db.execute("select count(*) as cnt from #{tablename}").first['cnt'].positive? rescue false) == true
        warn "Skipping table #{tablename} as it already has entries"
        warn "If the intention is to reprocess then the whole opendata.db file here: #{dir}"
        next
      end
      warn "Preparing entries in: #{tablename}"
      idx = 0
      IO.foreach(filename) do |line|
        begin
          $stderr.print "\r#{idx}"
          val = CSV.parse_line(line).to_a.reject(&:nil?).strip
          val = val.to_a.strip
          case idx
          when 0
            keys = val
          else
            entries << Hash[keys.zip(val)] if keys.size == val.size
          end
        rescue CSV::MalformedCSVError
          IO.write("#{filename}.error", line, mode: 'a')
        ensure
          idx += 1
        end
      end
      warn "Persisting entries in: #{tablename}"
      db.repsert([], entries, tablename) unless entries.blank?
    end
  end
end
require_relative 'local_fetcher' if File.exist?('lib/local_fetcher')
