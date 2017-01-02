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
require_relative 'config'
require_relative 'utils'

class JpegProcess
  def initialize(config, server, database)
    @stopped = Concurrent::AtomicBoolean.new(false)
    @find_files_completed = Concurrent::AtomicBoolean.new(false)
    @process_files_completed = Concurrent::AtomicBoolean.new(false)
    @server = server
    @database = database
    @config = config
  end

  def ping
    'pong'
  end

  def stop
    stopped.value = true
    'STOP jpeg_recompress'
  end

  def run
    @start_time = Time.now

    Thread.new do
      run_server
    end

    Thread.new do
      find_files
    end

    Thread.new do
      while find_files_completed.false? || database.not_processed_count > 0
        process_not_processed_files
      end

      @complete_time = Time.now
      puts(status)
      puts('COMPLETE')
    end

    sleep(1) while stopped.false?

    puts('exit jpeg_recompress')
    exit(0)
  end

  def run_server
    server.start
  rescue StandardError => e
    STDERR.puts(e)
    exit(1)
  end

  def find_files
    dir_enumerator = Utils.traversal_dir(config.src_dir, config.after, config.before)
    observable = Rx::Observable.of_enumerator(dir_enumerator)
                               .buffer_with_count(config.batch_count)
    observable.subscribe(
      lambda do |entries|
        database.transaction do
          entries.each do |entry|
            database.insert(entry.first, entry.last)
          end
        end
      end,
      ->(err) { STDERR.puts(err) },
      -> { find_files_completed.value = true }
    )
  end

  def process_not_processed_files
    filename_enumerator = database.find_not_processed_each(config.batch_count)
    observable = Rx::Observable.of_enumerator(filename_enumerator)
                               .buffer_with_count(config.batch_count)
    observable.subscribe(
      ->(files) { process_files(files) },
      ->(err) { STDERR.puts(err) },
      -> { process_files_completed.value = true }
    )
  end

  protected

  attr_reader :config, :stopped, :start_time, :complete_time, :find_files_completed, :process_files_completed,
              :server, :database

  def elsapsed_time_str(elapsed_time)
    str = ''
    days = (elapsed_time / 60 / 60 / 24).floor
    hours = (elapsed_time / 60 / 60).floor % 24
    minutes = (elapsed_time / 60).floor % 60
    seconds = elapsed_time.floor % 60

    str << "#{days}d " if days > 0
    str << "#{hours}h " if hours > 0
    str << "#{minutes}m " if minutes > 0
    str << "#{seconds}s"
    str
  end

  def nuvo_image(&_block)
    process = if nuvo_images.empty?
                NuvoImage::Process.new
              else
                nuvo_images.pop
              end
    yield process
    process.clear
    nuvo_images << process
  end

  private

  def nuvo_images
    @nuvo_images ||= Queue.new
  end
end
