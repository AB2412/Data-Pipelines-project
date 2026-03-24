require 'openc_bot'
require 'openc_bot/pseudo_machine_company_fetcher_bot'

require_relative 'common'
require_relative 'fetcher'
require_relative 'parser'
require_relative 'transformer'

module UsDeCompaniesFetcher
  extend OpencBot
  extend OpencBot::PseudoMachineCompanyFetcherBot
  extend self

  RAISE_WHEN_SAVING_INVALID_RECORD = true
  SAVE_RAW_DATA_ON_FILESYSTEM = 1
  DATASET_FOLDER = ENV.fetch('DATASET_FOLDER', "#{data_dir}")
  INVALID_OFFICER = Regexp.compile('^[^[:alnum:]]+$').freeze
  FileUtils.mkdir(DATASET_FOLDER) unless Dir.exist?(DATASET_FOLDER)
end
