require 'sqlite3'
require_relative 'database'

class RecompressDb < Database
  def initialize
    super(database_file)
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


  def insert(filename, stat)
    execute <<-SQL
      INSERT OR IGNORE INTO images VALUES("#{filename}",#{stat.size}, NULL);
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

  def not_processed_count
    rows = execute <<-SQL
      SELECT COUNT(*) FROM images where recompressed_size IS NULL
    SQL
    rows.first.first
  end

  def find_not_processed_each(batch_size = 5000)
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

  def database_file
    @database_file ||= File.join(File.dirname(__FILE__),'../recompress.db')
  end
end