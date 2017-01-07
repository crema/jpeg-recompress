require 'digest'
require_relative 'database'

class CompareDb < Database
  def initialize
    super(:ssim)
  end

  def insert(filename, _stat)
    md5 = Digest::MD5.hexdigest filename
    image = images.first(md5: md5, filename: filename)
    images.insert(md5: md5, filename: filename) unless image
  end

  def status
    sql = <<-SQL
      SELECT
        COUNT(*) AS count
        , SUM(ssim IS NOT NULL) AS compare_count
        , COALESCE(SUM(ssim > 0.8), 0) AS match_count
      FROM #{table_name}
    SQL
    db[sql].first
  end
end
