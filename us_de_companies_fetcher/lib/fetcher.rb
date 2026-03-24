require 'openc_bot/helpers/pseudo_machine_fetcher'
require 'pathname'
require 'net/sftp'

module UsDeCompaniesFetcher
  module Fetcher
    extend OpencBot
    extend OpencBot::Helpers::PseudoMachineFetcher
    extend self

    DATASET_BASED = true
    CREDENTIALS = get_bot_secret(nil, "couchdrop")

    def ftp_crawler
      paths = []
      warn "Connecting server ..."
      log_info = proc do |exception, try, elapsed_time, next_interval|
        $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
      end

      Retriable.retriable tries: 5, base_interval: 10, on_retry: log_info do
        Net::SFTP.start(CREDENTIALS["COUCHDROP_IP"],CREDENTIALS["USERNAME"], :password => CREDENTIALS["PASSWORD"]) do |sftp|
          warn "Server connected"
          sftp.dir.foreach("/us_de") do |entry|
            next unless entry.name.include? ".csv"
            csv_file_date = Date.parse(entry.name.gsub('.csv', ''))
            sub_directory_name = csv_file_date.strftime

            @sub_directory = "#{data_dir}/#{sub_directory_name}"
            file = "#{@sub_directory}/#{entry.name}"

            FileUtils.mkdir(@sub_directory) unless Dir.exist? (@sub_directory)
            unless File.exist? file
              sftp.download!("us_de/#{entry.name}", file)
              warn "File #{entry.name} downloaded ..."
              paths.push(@sub_directory)
            end
          end
        rescue Exception => e
          FileUtils.rm_rf(@sub_directory) if Dir.exist?(@sub_directory)
          raise e.message
        end
      end
      paths
    end

    def fetch_data_via_dataset(_options = {})
      folders = ENV['DATA_FOLDER'].blank? ? ftp_crawler : [ENV['DATA_FOLDER']]

      folders.each do |folder|
        sampled_at = Time.parse(folder.split('/').last).utc.iso8601
        entries = {}
        Dir.glob("#{folder}/*.*") do |filename|
          next if filename['.zip']

          warn filename
          entries[File.basename(filename)] = filename.sub(Dir.pwd, '').sub(%r{^/}, '')
        end
        raise 'Unexpected case of entries being blank!' if entries.blank?

        persist({ 'sampled_at' => sampled_at, 'retrieved_at' => Time.now.utc.iso8601, 'body' => entries, 'base_directory' => folder.sub(Dir.pwd, '').sub(%r{^/}, '') })
      end
    end
  end
end
