require_relative 'recompress_db'
require_relative 'jpeg_process'

class JpegRecompress < JpegProcess
  extend Jimson::Handler

  def initialize(config)
    super(config, Jimson::Server.new(self, port: 8998), RecompressDb.new)
  end

  def status
    elapsed_time = if complete_time
                     complete_time - start_time
                   else
                     Time.now - start_time
                   end
    count, recompressed_count, skip_count, size, recompressed_size, reduced_size = database.status.map(&:to_i)

    size = Filesize.new(size)
    reduced_percent = reduced_size.to_f / (recompressed_size + reduced_size).to_f * 100
    recompressed_size = Filesize.new(recompressed_size)
    processed_size = Filesize.new(recompressed_size + reduced_size)
    reduced_size = Filesize.new(reduced_size)

    percent = recompressed_count.to_f / count.to_f * 100
    percent = 0.0 if percent.nan?

    str = ''
    str << config.to_s
    str << "\n"
    str << '[DRY] ' if config.dry_run
    str << "start #{start_time}"
    str << ", complete #{complete_time}" if complete_time

    str << ", elapsed #{elsapsed_time_str(elapsed_time)}"

    str << "\n"
    str << "recompress #{recompressed_count}/#{count}(#{format('%.2f', percent)}%)"
    str << ", skip #{skip_count}"
    str << ", #{recompressed_size.pretty}/#{processed_size.pretty}/#{size.pretty}"
    str << ", reduce #{reduced_size.pretty}(#{format('%.2f', reduced_percent)}%)"

    str
  end

  def process_files(filenames)
    tmp_str = SecureRandom.hex
    tmp_count = Concurrent::AtomicFixnum.new
    results = Parallel.map(filenames, in_threads: config.thread_count) do |src_filename|
      return [src_filename, nil] unless File.exist?(src_filename)

      dest_tmp_filename = File.join(config.tmp_dir, "#{tmp_str}#{tmp_count.increment}" + '.jpg')

      recompressed_size = 0
      original_size = 0
      filename = Pathname.new(src_filename).relative_path_from(Pathname.new(config.src_dir))
      dest_filename = File.join(config.dest_dir, filename)
      skip = false

      copy_to_bak(src_filename, filename)

      begin
        nuvo_image do |process|
          image = process.read(src_filename)
          jpeg = process.lossy(image, dest_tmp_filename, format: :jpeg, quality: :high)

          original_size = image.size
          recompressed_size = jpeg.size

          unless config.dry_run
            FileUtils.mkdir_p(File.dirname(dest_filename))
            skip = true if original_size <= recompressed_size
          end
        end
      rescue StandardError => e
        STDOUT.print('F'.colorize(:red))
        STDERR.puts("fail: #{src_filename}")
        STDERR.puts(e)
        skip = true
      ensure
        unless config.dry_run
          if skip
            recompressed_size = original_size
            FileUtils.cp(src_filename, dest_filename) if dest_filename != src_filename
          else
            FileUtils.mv(dest_tmp_filename, dest_filename)
          end
        end

        File.delete(dest_tmp_filename) if File.exist?(dest_tmp_filename)

        prog_char = skip ? 'S'.colorize(:blue) : '.'.colorize(:green)
        STDOUT.print prog_char
      end
      [src_filename, recompressed_size]
    end

    print(' '.colorize(:white).on_white)
    database.transaction do
      results.each do |result|
        database.set_recompressed_size(result.first, result.last)
      end
    end
  end

  def copy_to_bak(src_filename, filename)
    return unless config.bak_dir

    bak_filename = File.join(config.bak_dir, filename)
    FileUtils.mkdir_p(File.dirname(bak_filename))
    FileUtils.cp(src_filename, bak_filename) if src_filename != bak_filename
  end
end
