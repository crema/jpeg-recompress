require 'sqlite3'

class Database
  def initialize(database_file)
    @logger = SemanticLogger['jpeg-recompress']

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

  attr_reader(
    :database,
    :logger,
    :mutex
  )

  def synchronize
    if Thread.current[:db_mutex]
      yield if block_given?
    else
      begin
        Thread.current[:db_mutex] = mutex
        mutex.synchronize do
          yield if block_given?
        end
      rescue StandardError => e
        logger.error e
        raise
      ensure
        Thread.current[:db_mutex] = nil
      end
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
