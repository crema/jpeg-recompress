require 'colorize'
require 'concurrent'
require 'facter'
require 'filesize'
require 'fileutils'
require 'jimson'
require 'nuvo_image'
require 'parallel'
require 'pathname'
require 'rx'
require 'time'
require_relative 'config'
require_relative 'utils'

class JpegProcess
  def initialize(config, server, database)
    @logger = SemanticLogger['jpeg-recompress']

    @stopped = Concurrent::AtomicBoolean.new(false)
    @find_files_completed = Concurrent::AtomicBoolean.new(false)
    @process_files_completed = Concurrent::AtomicBoolean.new(false)
    @server = server
    @database = database
    @config = config
    @snooze = true
  end

  def ping
    'pong'
  end

  def stop
    stopped.value = true
  end

  def find
    run_internal :find
  end

  def process
    run_internal :process
  end

  def run_internal(run_type)
    @start_time = Time.now

    Thread.abort_on_exception = true

    Thread.new { run_server }

    Thread.new do
      case run_type
      when :find then find_files
      when :process then process_internal
      end

      @complete_time = Time.now
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
    observable = Rx::Observable.of_enumerator(dir_enumerator)
                               .buffer_with_count(config.batch_count)
    observable.subscribe(
      lambda do |entries|
        database.transaction do
          entries.each { |entry| database.insert(entry.first, entry.last) }
        end
        sleep 0.1
      end,
      ->(err) { logger.error err },
      -> { find_files_completed.value = true }
    )
  end

  def process_internal
    active_start_time, active_end_time = config.active_start_end

    while find_files_completed.false? || database.not_all_processed?
      loop do
        time_now = Time.now
        active_start_time, active_end_time = config.active_start_end if active_end_time < time_now
        break if time_now.between?(active_start_time, active_end_time)
        sleep 60
      end

      process_not_processed_files
    end
  end

  def process_not_processed_files
    filename_enumerator = database.find_not_processed_each(config.batch_count)
    observable = Rx::Observable.of_enumerator(filename_enumerator)
    observable.subscribe(
      ->(rows) { process_files(rows) },
      ->(err) { logger.error err },
      -> { process_files_completed.value = true }
    )
  end

  protected

  attr_reader(
    :complete_time,
    :config,
    :database,
    :find_files_completed,
    :logger,
    :process_files_completed,
    :server,
    :snooze,
    :start_time,
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
