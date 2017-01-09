require 'digest'
require_relative 'database'

class CompareDb < Database
  def initialize
    super(:ssim)
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
