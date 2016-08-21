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
require_relative 'progress_db'

class JpegRecompress
  extend Jimson::Handler

  def initialize(dry_run: true,
                 src_dir: '', dest_dir: '', tmp_dir: '/mnt',
                 thread_count: 0, batch_count: 100,
                 before: Time.now, after: Time.parse('2000-01-01'))

    @dry_run = dry_run
    @src_dir = src_dir
    @dest_dir = dest_dir
    @tmp_dir = tmp_dir
    @thread_count = thread_count < 1 ? Facter.value('processors')['count'].to_i : thread_count
    @batch_count = batch_count
    @before = before
    @after = after

    @stopped = Concurrent::AtomicBoolean.new(false)
    @find_files_complete = Concurrent::AtomicBoolean.new(false)
    @recompress_files_complete = Concurrent::AtomicBoolean.new(false)
    @nuvo_images = Queue.new

    @server = Jimson::Server.new(self)
    @database = ProgressDb.new
  end

  def ping
    'pong'
  end

  def run
    @start_time = Time.now

    Thread.new do
      run_server
    end

    Thread.new do
      find_files
    end

    progress_thread = Thread.new do
      while find_files_complete.value == false || database.not_recompressed_count > 0
        recompress_files
      end

      @complete_time = Time.now
      puts(status)
      puts('COMPLETE')
    end

    until stopped.value
      sleep(1)
    end

    puts('exit jpeg_recompress')
    exit(0)
  end

  def config
    str = ''
    str << "src_dir: #{src_dir}\n"
    str << "dest_dir: #{dest_dir}\n"
    str << "tmp_dir: #{tmp_dir}\n"
    str << "thread_count: #{thread_count}\n"
    str << "batch_count: #{batch_count}\n"
    str << "between: #{after} ~ #{before}\n"
    str
  end

  def status
    elapsed_time =  Time.now.to_f - start_time.to_f

    count, recomppressed_count, skip_count, size, recompressed_size, reduced_size  = database.status.map {|c| c.to_i}

    size = Filesize.new(size)
    recompressed_size = Filesize.new(recompressed_size)
    processed_size = Filesize.new(recompressed_size + reduced_size)
    reduced_size = Filesize.new(reduced_size)

    percent = recomppressed_count.to_f/count.to_f * 100
    percent = 0.0 if percent.nan?

    str = ''
    str << config
    str << "\n"
    str << '[DRY] ' if dry_run
    str << "start #{start_time}"
    if complete_time
      str << ", complete #{complete_time}, elapsed #{Time.at(complete_time.to_f - start_time.to_f).utc.strftime("%H:%M:%S")}"
    else
      str << ", elapsed #{Time.at(elapsed_time).utc.strftime("%H:%M:%S")}"
    end
    str << "\n"
    str << "recompress #{recomppressed_count}/#{count}(#{format('%.2f',percent)}%)"
    str << ", skip #{skip_count}"
    str << ", #{recompressed_size.pretty}/#{processed_size.pretty}/#{size.pretty}"
    str << ", reduce #{reduced_size.pretty}(#{format('%.2f',reduced_size / (recompressed_size + reduced_size).to_f * 100)}%)"

    str
  end

  def stop
    stopped.value = true
    'STOP jpeg_recompress'
  end

  private

  attr_reader :dry_run, :src_dir, :dest_dir, :tmp_dir, :thread_count, :batch_count, :before, :after,
              :stopped, :start_time, :complete_time, :find_files_complete, :recompress_files_complete,
              :nuvo_images, :server, :database


  def run_server
    begin
      server.start
    rescue StandardError => e
      STDERR.puts(e)
      exit(1)
    end
  end

  def find_files
    subject = Rx::Subject.new
    observable = subject.as_observable
    observable = observable.buffer_with_count(batch_count)

    observable.subscribe(
        lambda do |entries|
          database.transaction do
            entries.each do |entry|
              database.insert(entry.first, entry.last.size)
            end
          end
        end,
        lambda {|err| STDERR.puts(err)},
        lambda { find_files_complete.value = true }
      )

    traversal_dir(src_dir) do |entry|
      subject.on_next(entry)
    end
    subject.on_completed
  end

  def recompress_files
    subject = Rx::Subject.new
    observable = subject.as_observable
    observable = observable.buffer_with_count(batch_count)

    observable.subscribe(
      lambda do |filenames|
        tmp_count = Concurrent::AtomicFixnum.new

        results = Parallel.map(filenames, in_threads: thread_count) do |src_filename|
          return [src_filename, nil] unless File.exist?(src_filename)

          dest_tmp_filename = File.join(tmp_dir, "tmp_#{tmp_count.increment}" + '.jpg')

          recompressed_size = 0
          original_size = 0
          filename = Pathname.new(src_filename).relative_path_from(Pathname.new(src_dir))


          begin
            nuvo_image do |process|
              image = process.read(src_filename)
              jpeg = process.lossy(image, dest_tmp_filename, format: :jpeg, quality: :high)

              original_size = image.size
              recompressed_size = jpeg.size

              unless dry_run
                dest_filename = File.join(dest_dir, filename)

                FileUtils.mkdir_p(File.dirname(dest_filename)) unless Dir.exist?(File.dirname(dest_filename))

                if File.exist?(dest_filename)
                  dest_size = File.size(dest_filename)
                  if dest_size > jpeg.size
                    FileUtils.mv(dest_tmp_filename, dest_filename)
                    recompressed_size = jpeg.size
                  else
                    recompressed_size = dest_size
                  end
                else
                  if original_size > recompressed_size
                    FileUtils.cp(dest_tmp_filename, dest_filename)
                  else
                    FileUtils.cp(src_filename, dest_filename)
                  end
                end
              end
            end
          rescue StandardError => e
            STDERR.print('F'.colorize(:red))
            original_size = recompressed_size = File.size(src_filename)
          ensure
            File.delete(dest_tmp_filename) if File.exist?(dest_tmp_filename)
            if original_size > recompressed_size
              STDOUT.print('.'.colorize(:green))
            else
              STDOUT.print('S'.colorize(:blue))
            end
          end
          [src_filename, recompressed_size]
        end

        print(' '.colorize(:white).on_white)
        database.transaction do
          results.each do |result|
            database.set_recompressed_size(result.first, result.last)
          end
        end
      end,
      lambda {|err| STDERR.puts(err)},
      lambda {recompress_files_complete.value = true}
    )

    database.find_not_recompressed_each(batch_count) do |filename|
      subject.on_next(filename)
    end
    subject.on_completed
  end

  def traversal_dir(dir, &block)
    dirs = [[dir, File.stat(dir)]]

    until dirs.empty?
      dirs.sort_by! {|dir| dir.last.ctime }
      current_entry = dirs.pop

      entries = Dir.entries(current_entry.first).select do |entry|
        !['.','..'].include?(entry)
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
        else
          if block_given? &&
            ['.jpg','.jpeg'].include?(File.extname(path).downcase) &&
            stat.ctime.between?(after, before)
            yield entry
          end
        end
      end
    end
  end

  def nuvo_image(&_block)
    process = nil
    if nuvo_images.empty?
      process = NuvoImage::Process.new
    else
      process = nuvo_images.pop
    end
    yield process
    process.clear
    nuvo_images << process
  end
end