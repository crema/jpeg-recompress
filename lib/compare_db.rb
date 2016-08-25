require 'sqlite3'
require_relative 'database'

class CompareDb < Database
  def initialize
    super(database_file)
    execute <<-SQL
      CREATE TABLE IF NOT EXISTS images(
        filename TEXT PRIMARY KEY,
        ssim DOUBLE
      );
    SQL
  end


  def insert(filename, stat)
    execute <<-SQL
      INSERT OR IGNORE INTO images VALUES("#{filename}", NULL);
    SQL
  end

  def set_ssim(filename, ssim)
    execute <<-SQL
      UPDATE images SET ssim = #{ssim} WHERE filename = "#{filename}";
    SQL
  end

  def status
    rows = execute <<-SQL
      SELECT COUNT(*), SUM(ssim IS NOT NULL), SUM(ssim > 0.8) FROM images
    SQL
    rows.first
  end

  def not_processed_count
    rows = execute <<-SQL
      SELECT COUNT(*) FROM images where ssim IS NULL
    SQL
    rows.first.first
  end

  def find_not_processed_each(batch_size = 5000)
    offset = 0
    loop do
      rows = execute <<-SQL
        SELECT filename, rowid FROM images WHERE rowid > #{offset} AND ssim IS NULL LIMIT #{batch_size}
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
    @database_file ||= File.join(File.dirname(__FILE__),'../compare.db')
  end
end