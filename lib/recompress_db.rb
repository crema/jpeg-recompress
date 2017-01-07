require 'digest'
require_relative 'database'

class RecompressDb < Database
  def initialize
    super(:comp_size)
  end

  def insert(filename, stat)
    md5 = Digest::MD5.hexdigest filename
    image = images.first(md5: md5, filename: filename)
    images.insert(md5: md5, filename: filename, orig_size: stat.size) unless image
  end

  def status
    sql = <<-SQL
      SELECT
        COUNT(*) AS count
        , SUM(comp_size IS NOT NULL) AS comp_count
        , COALESCE(SUM(comp_size = orig_size), 0) AS skip_count
        , SUM(orig_size) AS size
        , COALESCE(SUM(comp_size), 0) AS comp_size
        , COALESCE(SUM(orig_size - comp_size), 0) AS reduced_size
      FROM #{table_name}
    SQL
    db[sql].first
  end
end
