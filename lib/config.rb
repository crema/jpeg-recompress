require 'yaml'
require 'facter'

class Config
  def initialize(filename)
    config = YAML.load_file(filename)['jpeg_recompress']

    @dry_run = config.fetch('dry_run', true)
    @src_dir = config['src_dir'].to_s
    @dest_dir = config.fetch('dest_dir', src_dir).to_s
    @tmp_dir = config.fetch('tmp_dir', '/tmp').to_s
    @bak_dir = config['bak_dir'].to_s
    @thread_count = config.fetch('thread_count', Facter.value('processors')['count']).to_i
    @batch_count = config.fetch('batch_count', 100).to_i
    @before = config.fetch('before', Time.now).to_time
    @after = config.fetch('after', Time.parse('2000-01-01')).to_time

    @thread_count = Facter.value('processors')['count'].to_i if @thread_count.zero?
  end

  def valid_src_dir?
    File.directory?(src_dir)
  end

  def valid_dest_dir?
    File.directory?(dest_dir)
  end

  def valid_tmp_dir?
    File.directory?(tmp_dir)
  end

  def valid_bak_dir?
    if bak_dir
      File.directory?(bak_dir)
    else
      true
    end
  end

  def to_s
    str = ''
    str << "src_dir: #{src_dir}\n"
    str << "dest_dir: #{dest_dir}\n"
    str << "tmp_dir: #{tmp_dir}\n"
    str << "bak_dir: #{bak_dir}\n"
    str << "thread_count: #{thread_count}\n"
    str << "batch_count: #{batch_count}\n"
    str << "between: #{after} ~ #{before}\n"
    str
  end

  attr_reader :dry_run, :src_dir, :dest_dir, :tmp_dir,
              :thread_count, :batch_count,
              :before, :after, :bak_dir
end