require 'facter'
require 'yaml'

class Config
  def initialize(filename)
    config = YAML.load_file(filename)['jpeg_recompress']

    @dry_run = config.fetch('dry_run', true)

    # directory configs
    @src_dir = config['src_dir']
    @dest_dirs = config.fetch('dest_dirs', [src_dir])
    @tmp_dir = config.fetch('tmp_dir', '/run/shm')
    @bak_dir = config['bak_dir']

    @thread_count = config.fetch('thread_count', 1)
    @thread_count = Facter.value('processors')['count'] if @thread_count.zero?
    @batch_count = config.fetch('batch_count', 100)

    # time range for finding target files
    @before = config.fetch('before', Time.now).to_time
    @after = config.fetch('after', Time.parse('2000-01-01')).to_time

    # time configs for snoozing
    @active_start = config.fetch('active_start', '00:00')
    @active_for = config.fetch('active_for', 24).to_i
  end

  def valid_src_dir?
    File.directory?(src_dir)
  end

  def valid_dest_dirs?
    dest_dirs.all? { |d| File.directory? d }
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

  def active_start_end
    active_start_time = Time.parse(active_start)
    active_end_time = active_start_time + active_for * 3600
    [active_start_time, active_end_time]
  end

  def to_s
    <<~HEREDOC
      src_dir: #{src_dir}
      dest_dirs: #{dest_dirs.join(', ')}
      tmp_dir: #{tmp_dir}
      bak_dir: #{bak_dir}
      thread_count: #{thread_count}
      batch_count: #{batch_count}
      between: #{after} ~ #{before}
      active: #{active_start} + #{active_for} hours
    HEREDOC
  end

  attr_reader(
    :active_for,
    :active_start,
    :after,
    :bak_dir,
    :batch_count,
    :before,
    :dest_dirs,
    :dry_run,
    :src_dir,
    :thread_count,
    :tmp_dir
  )
end
