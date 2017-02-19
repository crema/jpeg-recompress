require 'yaml'

class Config
  def initialize(filename)
    config = YAML.load_file(filename)['jpeg_recompress']

    @dry_run = config.fetch('dry_run', true)

    # directory configs
    @src_dir = config['src_dir']
    @dst_dir = config['dst_dir']
    @tmp_dir = config.fetch('tmp_dir', '/run/shm')

    @thread_count = config.fetch('thread_count', 2)
    @thread_count = 2 if @thread_count.zero?
    @batch_count = config.fetch('batch_count', 1000)

    # time range for finding target files
    @before = config.fetch('before', Time.now).to_time
    @after = config.fetch('after', Time.parse('2000-01-01')).to_time
    @upload_after = config.fetch('upload_after', Time.now).to_time

    # time configs for snoozing
    @active_start = config.fetch('active_start', '00:00')
    @active_for = config.fetch('active_for', 24).to_i
  end

  def valid_src_dir?
    File.directory?(src_dir)
  end

  def valid_dst_dir?
    if dst_dir
      File.directory?(dst_dir)
    else
      true
    end
  end

  def valid_tmp_dir?
    File.directory?(tmp_dir)
  end

  def active_start_end
    active_start_time = Time.parse(active_start)
    active_end_time = active_start_time + active_for * 3600
    [active_start_time, active_end_time]
  end

  def to_s
    <<~HEREDOC
      src_dir: #{src_dir}
      dst_dir: #{dst_dir}
      tmp_dir: #{tmp_dir}
      thread_count: #{thread_count}
      batch_count: #{batch_count}
      between: #{after} ~ #{before}
      upload_after: #{upload_after}
      active: #{active_start} + #{active_for} hours
    HEREDOC
  end

  attr_reader(
    :active_for,
    :active_start,
    :after,
    :batch_count,
    :before,
    :dry_run,
    :dst_dir,
    :src_dir,
    :thread_count,
    :tmp_dir,
    :upload_after
  )
end
