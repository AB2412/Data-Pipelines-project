# encoding: UTF-8
require 'sqlite3'
require 'retriable'

# you may need to require other libraries here
require 'awesome_print'
require 'json'

# Extends Array class with a find_delete_by_keys methods which finds hashes in
# array which matches the keys
class Array
  def find_delete_by_keys(keys)
    select { |item| keys == item.keys }.each { |item| delete(item) }
  end

  def segregate( keys = first.keys )
    fragment, left_over = partition{|item| item.keys == keys }
    self.replace(left_over)
    fragment
  end
  
end

module SQLite3
  class Database

    def get( table_name )
      execute("select * from #{table_name};").map{|tuple|
        tuple.reject{|key, value|
          key.class.name == 'Fixnum'
        }.symbolize_keys
      }
    end

    def get_var(key)
      value = execute("select value from variables where key=?;",key).flatten.first
      if value.kind_of?( Hash )
        value = value['value']
      end
      JSON.parse( value ).symbolize_keys rescue value
    rescue SQLite3::SQLException => ex
      case ex.message
      when /no such table/
        create_table('variables',['key','value'],['key'])
        retry
      else
        raise ex
      end
    end

    def save_var(key, value)
      value = case value.class.name
              when 'Array', 'Hash', 'ActiveSupport::HashWithIndifferentAccess'
                JSON.generate(value)
              when 'Time', 'Date', 'String', 'FalseClass', 'TrueClass'
                value.to_s
              when 'Fixnum', 'Float'
                value
              when 'NilClass'
                nil
              else
                raise "Unhandled event class: #{value.class.name}"
              end
      execute("insert or replace into variables(key,value) values(?,?);",key,value)
    rescue SQLite3::SQLException => ex
      case ex.message
      when /no such table/
        create_table('variables',['key','value'],['key'])
        retry
      else
        raise ex
      end
    end

    def delete_var(key)
      execute("delete from variables where key=?",key)
    rescue SQLite3::SQLException => ex
      case ex.message
      when /no such table/
        create_table('variables',['key','value'],['key'])
        retry
      else
        raise ex
      end
    end

    def create_table( tbl_name, col_names, unique_keys = nil)
      if unique_keys.nil? || unique_keys.empty?
        query = "CREATE TABLE if not exists `#{tbl_name}` (#{col_names.map { |col_name| '`' + col_name.to_s + '`' }.join(',')})"
      else
        query = "CREATE TABLE if not exists `#{tbl_name}` (#{col_names.map { |col_name| '`' + col_name.to_s + '`' }.join(',')}, PRIMARY KEY (#{unique_keys.map { |unique_key| '`' + unique_key.to_s + '`' }.join(',') }))"
      end
      execute query
    end

    def pristine(tbl_name )
      execute("delete from `#{tbl_name}`" )
    end

    def add_column(tbl_name, col_name)
      execute("ALTER TABLE `#{tbl_name}` ADD COLUMN `#{col_name}`")
    end

    def repsert(unique_keys, tuple, table_name)
      tuple = [ tuple ] if Hash == tuple.class
      loop do
        persist(
          unique_keys,
          tuple.segregate,
          table_name
        )
        break if tuple.empty?
      end
    end

    def drop_table( tbl_name )
      execute( "drop table #{tbl_name}" )
    end

    private

    def persist(unique_keys, tuple, table_name)
      prepare_sql = "insert or replace into \
                    `#{table_name}`( #{tuple.first.keys.map { |key| '`' + key.to_s + '`' }.join(',') }) \
                    values(#{tuple.first.keys.length.times.map { '?' }.join(',') } )
      ".strip
      Retriable.retriable :on => SQLite3::BusyException, :tries => 20, :interval => 3 do
        transaction do |db|
          begin
            db.prepare(prepare_sql) do |statement|
              tuple.each do |row|
                statement.execute row.values.map{ |item| 
                  case item.class.name
                  when 'Array', 'Hash', 'ActiveSupport::HashWithIndifferentAccess'
                    JSON.generate(item)
                  when 'Time', 'Date', 'FalseClass', 'TrueClass'
                    item.to_s
                  when 'String'
                    item
                  when 'Fixnum', 'Float'
                    item
                  when 'NilClass'
                    nil
                  else
                    raise "Unhandled event class: #{item.class.name}"
                  end
                }
              end
            end
          rescue SQLite3::SQLException => ex
            case ex.message
            when /no such table/
              create_table(table_name, tuple.first.keys, unique_keys)
              retry
            when /no column named/
              add_column(table_name, ex.message.split(/no column named/).last.strip)
              retry
            else
              raise ex
            end
          end
        end
      end
    end
  end
end
