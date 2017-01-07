require 'digest'
require 'sequel'

class Database
  def initialize(name)
    @logger = SemanticLogger['jpeg-recompress']

    @check_column_name = name
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

  def update(pairs)
    id = pairs.delete :id
    images.where(id: id).update(pairs)
  end

  def not_all_processed?
    images.first(check_column_name => nil)
  end

  def find_not_processed_each(batch_size = 1000)
    Enumerator.new do |y|
      offset = 0
      loop do
        rows = images.where(check_column_name => nil)
                     .select(:id, :md5, :filename)
                     .limit(batch_size, offset)
                     .all
        count = rows.count
        break if count.zero?

        offset += count
        y << rows
      end
    end
  end

  private

  attr_reader(
    :check_column_name,
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
      index [:orig_size, :comp_size]
    end
  end
end
