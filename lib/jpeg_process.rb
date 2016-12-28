require 'nuvo_image'
require 'facter'
require 'jimson'
require 'concurrent'
require 'parallel'
require 'pathname'
require 'fileutils'
require 'filesize'
require 'rx'
require 'colorize'
require_relative 'config'

class JpegProcess
  def initialize(config, server, database)
    @stopped = Concurrent::AtomicBoolean.new(false)
    @find_files_complete = Concurrent::AtomicBoolean.new(false)
    @process_files_complete = Concurrent::AtomicBoolean.new(false)
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
      file_files
    end

    Thread.new do
      while find_files_complete.value == false || database.not_processed_count > 0
        process_not_processed_files
      end

      @complete_time = Time.now
      puts(status)
      puts('COMPLETE')
    end

    sleep(1) until stopped.value

    puts('exit jpeg_recompress')
    exit(0)
  end

  def run_server
    server.start
  rescue StandardError => e
    STDERR.puts(e)
    exit(1)
  end

  def file_files
    subject = Rx::Subject.new
    observable = subject.as_observable
    observable = observable.buffer_with_count(config.batch_count)

    observable.subscribe(
      lambda do |entries|
        database.transaction do
          entries.each do |entry|
            database.insert(entry.first, entry.last)
          end
        end
      end,
      ->(err) { STDERR.puts(err) },
      -> { find_files_complete.value = true }
    )

    traversal_dir(config.src_dir) do |entry|
      subject.on_next(entry)
    end
    subject.on_completed
  end

  def process_not_processed_files
    subject = Rx::Subject.new
    observable = subject.as_observable
    observable = observable.buffer_with_count(config.batch_count)

    observable.subscribe(
      lambda do |files|
        process_files(files)
      end,
      ->(err) { STDERR.puts(err) },
      -> { process_files_complete.value = true }
    )

    database.find_not_processed_each(config.batch_count) do |filename|
      subject.on_next(filename)
    end
    subject.on_completed
  end

  protected

  attr_reader :config, :stopped, :start_time, :complete_time, :find_files_complete, :process_files_complete,
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

  def traversal_dir(dir)
    dirs = [[dir, File.stat(dir)]]

    until dirs.empty?
      dirs.sort_by! { |d| d.last.ino }
      current_entry = dirs.pop

      entries = Dir.entries(current_entry.first).select do |entry|
        !['.', '..'].include?(entry)
      end

      entries = entries.map do |entry|
        File.join(current_entry.first, entry)
      end

      entries = entries.map do |entry|
        [entry, File.stat(entry)]
      end
      entries.each do |entry|
        path, stat = entry
        if stat.directory?
          dirs.push(entry)
        elsif block_given? &&
              ['.jpg', '.jpeg'].include?(File.extname(path).downcase) &&
              stat.ctime.between?(config.after, config.before)
          yield entry
        end
      end
    end
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
