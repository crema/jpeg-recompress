require 'sqlite3'
require 'fileutils'
require 'rx'
require 'nuvo_image'
require 'parallel'
require 'concurrent'
require 'filesize'

require_relative 'lib/progress_db'

class JpegRecompress
  def initialize(args)
    raise 'require dest=' unless args['dest']

    @dest = args['dest']
    @db = ProgressDb.new(args.fetch('db','progress.db'))
    @thread = args.fetch('thread',4).to_i
    @dry = args['dry']
    @force = args['force']

    @find_files_complete = Concurrent::AtomicBoolean.new(false)
    @recompress_files_complete = Concurrent::AtomicBoolean.new(false)
  end

  def recompress
    @start_time = Time.now.to_f

    if force
      puts 'reset recompress size not small'
      db.reset_recompress_size_not_small
    end

    _, recomppressed_count, skip_sount = db.total_count.map {|c| c.to_i}
    @start_recompressed_count = recomppressed_count

    find_files_thread = Thread.new {find_files}
    recompress_files_thread = Thread.new {recompress_files}

    while find_files_complete.value == false || recompress_files_complete.value == false
      print_progress
      sleep(1)
    end

    print_progress
    puts "\ncomplete"

    find_files_thread.join
    recompress_files_thread.join
  end

  private

  attr_reader :dest, :db, :force, :thread, :dry, :reduced,
              :find_files_complete, :recompress_files_complete, :start_time,
              :start_recompressed_count

  def print_progress
    elapsed_time =  Time.now.to_f - start_time

    count, recomppressed_count, skip_sount = db.total_count.map {|c| c.to_i}
    size, recompressed_size, reduced_size = db.total_size.map {|s| Filesize.new(s)}

    remain_time = (count - recomppressed_count) / ((recomppressed_count - start_recompressed_count) / elapsed_time)

    print "\r"
    print "recompress #{recomppressed_count}/#{count}(#{format('%.2f',recomppressed_count.to_f/count.to_f * 100)}%)/#{size.pretty}"
    print ", skip #{skip_sount}"
    print ", #{recompressed_size.pretty}"
    print ", reduce #{reduced_size.pretty}"
    print ", elapsed #{Time.at(elapsed_time).utc.strftime("%H:%M:%S")}"
    if remain_time.infinite?
      print ", remain "
    else
      print ", remain #{Time.at(remain_time).utc.strftime("%H:%M:%S")}"
    end
    print ' -- dry -- ' if dry
  end

  def find_files
    subject = RX::Subject.new
    subject
      .as_observable
      .select {|filename| ['.jpg','.jpeg'].include?(File.extname(filename).downcase)}
      .buffer_with_count(1000)
      .subscribe(
        lambda do |filenames|
          db.transaction do
            filenames.each do |filename|
              db.insert(filename, File.size(filename))
            end
          end
        end,
        lambda {|err| raise err},
        lambda { find_files_complete.value = true }
      )

    traversal_dir(dest) do |filename|
      subject.on_next(filename)
    end
    subject.on_completed
  end

  def recompress_files
    subject = RX::Subject.new
    subject
      .as_observable
      .buffer_with_count(16)
      .subscribe(
        lambda do |filenames|
          sizes = Parallel.map(filenames, in_threads: thread) do |filename|
            size = 0
            begin
              NuvoImage.process do |process|
                tempfile = Tempfile.new(File.basename(filename))
                image = process.read(filename)
                jpeg = process.jpeg(image, tempfile.path, quality: 0.966, search: 3, gray_ssim: false)

                if jpeg.size < image.size
                  size = jpeg.size
                  FileUtils.cp(tempfile.path, filename) unless dry
                else
                  size = image.size
                end
                tempfile.delete
              end
            rescue StandardError => e
              puts "\nfail #{filename}: #{e}"
              size = File.size(filename)
            end
            size
          end

          db.transaction do
            filenames.each_with_index do |filename, i|
              db.set_recompress_size(filename, sizes[i])
            end
          end
        end,
        lambda {|err| raise err},
        lambda {recompress_files_complete.value = true}
      )

    while find_files_complete.value == false || db.count_not_recompressed > 0
      db.find_not_recompress_each do |filename|
        subject.on_next(filename)
      end
    end
    subject.on_completed
  end

  def traversal_dir(dir)
    queue = Queue.new
    queue << dir
    while !queue.empty?
      current_dir = queue.pop

      Dir.entries(current_dir).each do |entry|
        next if ['.','..'].include?(entry)
        entry = File.join(current_dir, entry)
        if File.directory?(entry)
          queue << entry
        else
          yield entry if block_given?
        end
      end
    end
  end
end

JpegRecompress.new(ARGV.map {|arg| arg.split('=')}.to_h).recompress