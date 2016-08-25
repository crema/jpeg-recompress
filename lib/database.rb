require 'sqlite3'

class Database
  def initialize(database_file)
    @mutex = Mutex.new
    @database_file = database_file
    @database = SQLite3::Database.new(database_file)
  end

  def clean
    File.delete(database_file) if File.exist?(database_file)
  end

  def transaction
    synchronize do
      begin_transaction
      yield
      commit
    end
  end

  def execute(sql)
    synchronize do
      database.execute(sql)
    end
  end

  private

  attr_reader :mutex, :database

  def synchronize
    if Thread.current[:db_mutex]
      yield if block_given?
    else
      result = nil
      Thread.current[:db_mutex] = mutex
      mutex.synchronize do
        result =yield if block_given?
      end
      Thread.current[:db_mutex] = nil
      result
    end
  end

  def begin_transaction
    database.execute <<-SQL
      BEGIN;
    SQL
  end

  def commit
    database.execute <<-SQL
      COMMIT;
    SQL
  end
end