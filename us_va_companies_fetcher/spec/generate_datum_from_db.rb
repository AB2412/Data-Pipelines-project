# encoding: UTF-8
require_relative 'spec_helper'
require 'sqlite3'
require 'active_support'
require 'active_support/core_ext'

describe 'backport output check' do
  if ENV['DATABASE']
    db = SQLite3::Database.new(ENV['DATABASE'])
    db.results_as_hash = true
    comprehensive_check do |uid|
      it 'process_datum should be able write processed files' do
        raw = db.execute('select * from ocdata where company_number=?', uid)
        unless raw.blank?
          response_write("output_files/#{uid}.json", JSON.pretty_generate(tuple_to_schema(raw.first)))
        end
      end
    end
  else
    raise 'No backport database specified'
  end
end

