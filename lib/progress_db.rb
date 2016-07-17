require 'sqlite3'

class ProgressDb
  def initialize(db)
    @db = SQLite3::Database.new(db)
    init_db
  end

  attr_reader :db

  def transaction
    begin_transaction
    yield
    commit
  end

  def insert(filename, size)
    execute <<-SQL
      INSERT OR IGNORE INTO images VALUES("#{filename}",#{size}, NULL);
    SQL
  end

  def reset_recompress_size_not_small
    rows = execute <<-SQL
      UPDATE images SET recompress_size = NULL WHERE original_size = recompress_size;
    SQL
    rows.first
  end

  def set_recompress_size(filename, recompress_size)
    execute <<-SQL
      UPDATE images SET recompress_size = #{recompress_size} WHERE filename = "#{filename}";
    SQL
  end

  def total_size
    rows = execute <<-SQL
        SELECT SUM(original_size), SUM(recompress_size), SUM(original_size - recompress_size) FROM images
    SQL
    rows.first
  end

  def total_count
    rows = execute <<-SQL
      SELECT COUNT(filename), SUM(recompress_size IS NOT NULL), SUM(recompress_size = original_size) FROM images
    SQL
    rows.first
  end

  def not_recompressed_count
    rows = execute <<-SQL
      SELECT COUNT(filename) FROM images where recompress_size IS NULL
    SQL
    rows.first.first
  end

  def find_not_recompress_each(batch_size = 5000)
    offset = 0
    loop do
      rows = execute <<-SQL
        SELECT filename, rowid FROM images WHERE rowid > #{offset} AND recompress_size IS NULL LIMIT #{batch_size}
      SQL
      return if rows.empty?

      offset += rows.last.last
      rows.each do |row|
        yield row.first
      end
    end
  end

  private

  def begin_transaction
    execute <<-SQL
      BEGIN;
    SQL
  end

  def commit
    execute <<-SQL
      COMMIT;
    SQL
  end

  def init_db
    execute <<-SQL
      CREATE TABLE IF NOT EXISTS images(
        filename TEXT PRIMARY KEY,
        original_size INTEGER,
        recompress_size INTEGER
      );
    SQL
  end

  def execute(sql)
    db.execute(sql)
  end

end