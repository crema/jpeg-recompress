require 'sqlite3'

class ProgressDb
  def initialize
    @mutex = Mutex.new
    @database = SQLite3::Database.new(database_file)

    execute <<-SQL
      CREATE TABLE IF NOT EXISTS images(
        filename TEXT PRIMARY KEY,
        original_size INTEGER,
        recompressed_size INTEGER
      );
    SQL
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS size_index ON images (original_size, recompressed_size);
    SQL
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

  def insert(filename, size)
    execute <<-SQL
      INSERT OR IGNORE INTO images VALUES("#{filename}",#{size}, NULL);
    SQL
  end

  def set_recompressed_size(filename, recompressed_size)
    execute <<-SQL
      UPDATE images SET recompressed_size = #{recompressed_size} WHERE filename = "#{filename}";
    SQL
  end

  def status
    rows = execute <<-SQL
      SELECT COUNT(*), SUM(recompressed_size IS NOT NULL), SUM(recompressed_size = original_size), SUM(original_size), SUM(recompressed_size), SUM(original_size - recompressed_size) FROM images
    SQL
    rows.first
  end

  def not_recompressed_count
    rows = execute <<-SQL
      SELECT COUNT(*) FROM images where recompressed_size IS NULL
    SQL
    rows.first.first
  end

  def find_not_recompressed_each(batch_size = 5000)
    offset = 0
    loop do
      rows = execute <<-SQL
        SELECT filename, rowid FROM images WHERE rowid > #{offset} AND recompressed_size IS NULL LIMIT #{batch_size}
      SQL
      return if rows.empty?

      offset += rows.last.last
      rows.each do |row|
        yield row.first
      end
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


  def database_file
    @database_file ||= File.join(File.dirname(__FILE__),'../progress.db')
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

  def execute(sql)
    synchronize do
      database.execute(sql)
    end
  end

end