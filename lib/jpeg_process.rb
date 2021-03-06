require 'colorize'
require 'concurrent'
require 'filesize'
require 'fileutils'
require 'jimson'
require 'nuvo_image'
require 'parallel'
require 'pathname'
require 'time'
require_relative 'config'
require_relative 'database'
require_relative 'utils'

class JpegProcess
  JPEG_EXT = ['.jpg', '.jpeg'].freeze

  def initialize(config, server, database)
    @logger = SemanticLogger['jpeg-recompress']

    @stopped = Concurrent::AtomicBoolean.new(false)
    @server = server
    @database = database
    @config = config
  end

  def ping
    'pong'
  end

  def stop
    stopped.value = true
  end

  def run(run_type)
    @start_time = Time.now

    Thread.abort_on_exception = true

    Thread.new { run_server }

    Thread.new do
      case run_type
      when :find then find_files
      when :process then process_internal
      when :process_failed then process_internal(for_failed: true)
      when :upload then upload_internal
      when :upload_failed then upload_internal(for_failed: true)
      end

      print_completed
      stopped.value = true
    end

    sleep(1) while stopped.false?

    logger.info 'exit processing'
    exit(0)
  end

  def run_server
    server.start
  rescue StandardError => e
    logger.error e
    exit(1)
  end

  def find_files
    dir_enumerator = Utils.traversal_dir(config.src_dir, config.after, config.before)
    dir_enumerator.each_slice(config.batch_count) do |entries|
      database.transaction do
        entries.each do |path, stat|
          is_jpeg = JPEG_EXT.include?(File.extname(path).downcase)
          database.insert(path, stat.size, is_jpeg, stat.ctime)
        end
      end
    end

    complete_time = Time.now
  rescue StandardError => e
    logger.error e
  end

  def process_internal(for_failed: false)
    active_start_time, active_end_time = config.active_start_end

    filename_enumerator = if for_failed
                            database.find_failed_each(config.batch_count)
                          else
                            database.find_not_processed_each(config.batch_count)
                          end
    filename_enumerator.each do |rows|
      loop do
        time_now = Time.now
        active_start_time, active_end_time = config.active_start_end if active_end_time < time_now
        break if time_now.between?(active_start_time, active_end_time)
        sleep 60
      end

      process_files(rows)
      GC.start
    end

    complete_time = Time.now
  rescue StandardError => e
    logger.error e
  end

  def upload_internal(for_failed: false)
    active_start_time, active_end_time = config.active_start_end

    filename_enumerator = if for_failed
                            database.find_failed_each(config.batch_count)
                          else
                            database.find_not_processed_each(config.batch_count)
                          end
    filename_enumerator.each do |rows|
      loop do
        time_now = Time.now
        active_start_time, active_end_time = config.active_start_end if active_end_time < time_now
        break if time_now.between?(active_start_time, active_end_time)
        sleep 60
      end

      upload_files(rows)
      GC.start
    end

    complete_time = Time.now
  rescue StandardError => e
    logger.error e
  end

  protected

  attr_accessor(
    :complete_time,
    :start_time
  )

  attr_reader(
    :config,
    :database,
    :logger,
    :server,
    :stopped
  )

  def print_completed
    logger.info 'COMPLETE'
    logger.info status
  end

  def elsapsed_time_str(elapsed_time)
    days = (elapsed_time / 60 / 60 / 24).floor
    hours = (elapsed_time / 60 / 60).floor % 24
    minutes = (elapsed_time / 60).floor % 60
    seconds = elapsed_time.floor % 60

    str = ''
    str << "#{days}d " if days.positive?
    str << "#{hours}h " if hours.positive?
    str << "#{minutes}m " if minutes.positive?
    str << "#{seconds}s"
    str
  end

  def nuvo_image(&_block)
    process = nuvo_images.empty? ? NuvoImage::Process.new : nuvo_images.pop
    yield process
    process.clear
    nuvo_images << process
  end

  def nuvo_images
    @nuvo_images ||= Queue.new
  end
end
