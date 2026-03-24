require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'openc_bot/helpers/dates'
require 'spreadsheet'
require_relative 'web_scraper'

module CaOnCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::PseudoMachineCompanyFetcherBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend OpencBot::Helpers::Dates
    extend OpencBot::Helpers::PsuedoMachineRegisterMethods

    module_function
    DATASET_BASED = true
    CREDENTIALS = get_bot_secret("ca_on")
    WEBSHARE_CREDENTIALS = get_bot_secret(nil, "webshare")
    set_credentials(CREDENTIALS.merge(WEBSHARE_CREDENTIALS))

    def folders
      @folders ||= if ENV['DATA_FOLDER']
                     [ENV['DATA_FOLDER']]
                   else
                     crawler
                   end
      @folders
    end

    def read_txt_file
      txt_file = Dir.glob("#{@data_folder}/*.txt").first rescue nil
      txt_file ? File.readlines(txt_file).map{|e| JSON.parse(e)}.map{|e| e["company_number"]} : []
    end

    def init_working_folder
      @data_folder = working_data_folder || "#{data_dir}/#{Time.now.strftime('%Y-%m-%d_%H%M')}_processing"
      unless Dir.exist?(@data_folder)
        FileUtils.mkdir_p(@data_folder)
      end
      @fetch_company_numbers = read_txt_file
    end

    def init_db
      db_file = "db/caoncompaniesfetcher.db"
      @db = SQLite3::Database.new(db_file, results_as_hash: true)
      if File.zero?(db_file)
        Open3.capture3("sqlite3 -batch #{db_file} '.read lib/schema.sql'")
      end
    end

    def crawler
      init_db
      init_working_folder
      # Search all by company_number
      Thread.abort_on_exception = true

      collector_thread = Thread.new{searching_company_numbers}
      older_months_collector_thread = Thread.new do
        collector_thread.join
        searching_company_numbers(false)
      end

      processor_thread = Thread.new{ process_company_data}
      stale_thread = Thread.new do
        processor_thread.join
        update_stale
      end

      [older_months_collector_thread, stale_thread].each(&:join)
      fetch_gaps
      return nil if Dir.empty?(@data_folder)
      @db.execute("DELETE FROM registry_queue WHERE uid IN (#{(['?'] * @fetch_company_numbers.length).join(', ')})", @fetch_company_numbers)
      [@data_folder]
    end

    def fetch_gaps
      puts "********** In the fetch_gaps ******************"
      highest_gap_uid = get_var('highest_gap_uid') || INITIAL_GAP_UID
      start_id = highest_gap_uid.to_i
      end_id = start_id + GAPS_RANGE

      query = "SELECT CAST(company_number AS INTEGER) FROM ocdata WHERE CAST(company_number AS INTEGER) BETWEEN ? AND ? ORDER BY CAST(company_number AS INTEGER)"
      existing_ids = @db.execute(query, [start_id, end_id]).flatten

      # Generate complete range and find missing ones
      complete_range = (start_id..end_id).to_a
      missing_ids = complete_range - existing_ids

      missing_ids = missing_ids.map{|id| id/10}

      fetch_gaps_from_numbers(missing_ids.uniq)

      save_var('highest_gap_uid', end_id.to_s)
    end

    def iterate_bulk_companies(bulk_uids, company_type)
      Parallel.each(bulk_uids.each_slice(RECORDS_PER_THREAD), in_threads: MAX_THREAD.to_i) do |company_numbers|
        log_info = Proc.new do |exception, try, elapsed_time, next_interval|
          $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
        end
        Retriable.retriable :tries => 3, :base_interval => 30, :on_retry => log_info do
          mechanize_process_company_numbers(company_numbers, company_type)
        end
      end
    end

    def process_company_data
      warn "In the Process company Data"
      begin
        Timeout::timeout(PROCESS_RUNTIME_LIMIT) {
          COMPANY_TYPES.each do |company_type|
            bulk_uids = @db.execute("select uid from registry_queue where company_type = ? and uid not in (select company_number from ocdata) limit(#{QUEUE_PROCESS_LIMIT})", company_type).map{|res| res['uid']} rescue []
            iterate_bulk_companies(bulk_uids, company_type)
          end
        }
      rescue Timeout::Error
        warn "Reach the run-time limit process_company_data"
      end
    end

    def update_stale(stale_count=nil)
      warn "********** In the update_stale ******************"
      if registry_queue_count > QUEUE_PENDING_LIMIT
        warn "Registry queue count is too high: #{registry_queue_count}, skipping stale update."
        return {:update_stale_output => "Registry queue count is too high: #{registry_queue_count}, skipping stale update."}
      end
      begin
        Timeout::timeout(PROCESS_RUNTIME_LIMIT) {
          COMPANY_TYPES.each do |company_type|
            active_stale_records = get_stale_records(ACTIVE_STATUS_STALE_DAYS, true, company_type)
            inactive_stale_records =  get_stale_records(INACTIVE_STATUS_STALE_DAYS, false, company_type)
            stale_records = active_stale_records + inactive_stale_records
            iterate_bulk_companies(stale_records, company_type)
          end
        }
      rescue SystemExit,Interrupt, OpencBot::OutOfPermittedHours, OpencBot::SourceClosedForMaintenance, Timeout::Error => ex
        warn "Reach the run-time limit update_stale"
        {:update_stale_output => ex.message}
      rescue Exception => ex
        raise ex
      end
    end

    def get_stale_records(stale_limit, stale_flag = true, company_type)
      company_type_condition = company_type == "Partnerships" ? "company_type LIKE '%Partnership'" : "company_type NOT LIKE '%Partnership'"
      current_status_condition = stale_flag ? "current_status != 'Inactive' OR current_status IS NULL AND (DATE(dissolution_date) >= #{Date.today} OR dissolution_date IS NULL)" : "current_status = 'Inactive' OR DATE(dissolution_date) < #{Date.today}"
      stale_count_limit = stale_flag ? ACTIVE_STATUS_STALE_COUNT : INACTIVE_STATUS_STALE_COUNT
      query = "select company_number from ocdata where (retrieved_at IS NULL OR strftime('%s', retrieved_at) < strftime('%s',  '#{Date.today - stale_limit}')) AND (#{current_status_condition}) AND (#{company_type_condition}) order by date(retrieved_at) limit #{stale_count_limit}"
      @db.execute(query).map{|e| e["company_number"]}
    end

    def fetch_data_via_dataset(_options = {})
      if folders.blank?
        warn 'Either the data folder is not set, or there are no files to process in the data folder.'
        return nil
      end

      folders.each do |folder|
        sampled_at = Time.parse(folder.split('/').last.gsub("_processing","")).utc.iso8601
        entries = {}
        Dir.glob("#{folder}/*.txt") do |filename|
          warn filename
          entries[File.basename(filename, '.*')] = filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries,
                  'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
