require 'digest'
require 'sequel'

class Database
  def initialize
    @logger = SemanticLogger['jpeg-recompress']

    @db_config = YAML.load_file('db.yml')['default']
    @db = Sequel.connect db_config

    @table_name = db_config['table'].to_sym
    create_jpegfile_table

    @images = db[table_name]
  end

  def clean
    db.drop_table table_name
  end

  def transaction
    db.transaction do
      yield
    end
  end

  def insert(filename, orig_size, is_jpeg, ctime)
    md5 = Digest::MD5.hexdigest filename
    image = images.first(md5: md5, filename: filename)
    args = { md5: md5, filename: filename, orig_size: orig_size, is_jpeg: is_jpeg, ctime: ctime }
    if image
      images.where(id: image[:id]).update(args)
    else
      images.insert(args)
    end
  end

  def update(pairs)
    id = pairs.delete :id
    images.where(id: id).update(pairs)
  end

  def find_not_processed_each(batch_size, nil_column_name)
    Enumerator.new do |y|
      last_id = 0
      loop do
        rows = images.where(nil_column_name => nil)
                     .where('id > ?', last_id)
                     .select(:id, :md5, :filename, :orig_size, :is_jpeg, :ctime)
                     .order(:id)
                     .limit(batch_size)
                     .all
        break if rows.count.zero?

        last_id = rows.last[:id]
        y << rows
      end
    end
  end

  def recomp_status
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

  def compare_status
    sql = <<-SQL
      SELECT
        COUNT(*) AS count
        , SUM(ssim IS NOT NULL) AS compare_count
        , COALESCE(SUM(ssim > 0.8), 0) AS match_count
      FROM #{table_name}
    SQL
    db[sql].first
  end

  private

  attr_reader(
    :db_config,
    :db,
    :images,
    :logger,
    :table_name
  )

  def create_jpegfile_table
    db.create_table?(table_name) do
      primary_key :id
      String :md5, fixed: true, size: 32, index: true, null: false
      String :filename, size: 4096, null: false
      Integer :orig_size
      Integer :comp_size
      Float :ssim
      TrueClass :is_jpeg, null: false, default: true
      DateTime :ctime, index: true

      index [:orig_size, :comp_size]
    end
  end
end

class RecompressDb < Database
  def find_not_processed_each(batch_size)
    super(batch_size, :comp_size)
  end

  def find_failed_each(batch_size)
    Enumerator.new do |y|
      last_id = 0
      loop do
        rows = images.where(comp_size: -1)
                     .where('id > ?', last_id)
                     .select(:id, :md5, :filename, :orig_size, :is_jpeg, :ctime)
                     .order(:id)
                     .limit(batch_size)
                     .all
        break if rows.count.zero?

        last_id = rows.last[:id]
        y << rows
      end
    end
  end
end

class CompareDb < Database
  def find_not_processed_each(batch_size)
    super(batch_size, :ssim)
  end
end
