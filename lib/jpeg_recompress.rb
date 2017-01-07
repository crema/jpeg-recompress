require_relative 'jpeg_process'
require_relative 'recompress_db'
require_relative 's3_client'

class JpegRecompress < JpegProcess
  extend Jimson::Handler

  def initialize(config)
    super(config, Jimson::Server.new(self, port: 8998), RecompressDb.new)
    @s3_client = S3Client.new
  end

  def status
    elapsed_time = (complete_time || Time.now) - start_time
    result = database.status
    count = result[:count]
    comp_count = result[:comp_count]
    skip_count = result[:skip_count]
    size = result[:size]
    comp_size = result[:comp_size]
    reduced_size = result[:reduced_size]

    size = Filesize.new(size)
    reduced_percent = reduced_size.to_f / (comp_size + reduced_size).to_f * 100
    comp_size = Filesize.new(comp_size)
    processed_size = Filesize.new(comp_size + reduced_size)
    reduced_size = Filesize.new(reduced_size)

    percent = comp_count.to_f / count.to_f * 100
    percent = 0.0 if percent.nan?

    str = "\n#{config}\n"
    str << '[DRY] ' if config.dry_run
    str << "start #{start_time}"
    str << ", complete #{complete_time}" if complete_time
    str << ", elapsed #{elsapsed_time_str(elapsed_time)}"
    str << "\n"
    str << "recompress #{comp_count}/#{count}(#{format('%.2f', percent)}%)"
    str << ", skip #{skip_count}"
    str << ", #{comp_size.pretty}/#{processed_size.pretty}/#{size.pretty}"
    str << ", reduce #{reduced_size.pretty}(#{format('%.2f', reduced_percent)}%)"
    str
  end

  def process_files(rows)
    tmp_str = SecureRandom.hex
    tmp_count = Concurrent::AtomicFixnum.new

    results = Parallel.map(rows, in_threads: config.thread_count) do |row|
      src_filename = row[:filename]
      return nil unless File.exist?(src_filename)

      filename = Pathname.new(src_filename).relative_path_from(Pathname.new(config.src_dir))
      copy_to_bak(src_filename, filename)

      orig_size = 0
      comp_size = 0
      tmp_filename = File.join(config.tmp_dir, "#{tmp_str}#{tmp_count.increment}.jpg")
      dest_filenames = config.dest_dirs.map { |d| File.join(d, filename) }
      skip = false

      begin
        orig_size, comp_size = compress_image(src_filename, tmp_filename)

        @s3_client.put_object(tmp_filename, filename) unless config.dry_run

        skip = orig_size <= comp_size
      rescue StandardError => e
        Utils.print_fail
        logger.error "fail: #{src_filename}"
        logger.error e
        skip = true
      ensure
        unless config.dry_run
          dests = if skip
                    comp_size = orig_size
                    dest_filenames.select { |fname| fname != src_filename }
                  else
                    dest_filenames
                  end
          copy_file_to_dests(tmp_filename, dests)
        end

        File.delete(tmp_filename) if File.exist?(tmp_filename)

        Utils.print_skip_or_dot(skip)
      end

      { id: row[:id], comp_size: comp_size }
    end

    print(' '.colorize(:white).on_white)

    database.transaction do
      results.compact.each do |result|
        database.update result
      end
    end
  end

  private

  def copy_to_bak(src_filename, filename)
    return if config.dry_run
    return unless config.bak_dir

    bak_filename = File.join(config.bak_dir, filename)
    FileUtils.mkdir_p(File.dirname(bak_filename))
    FileUtils.cp(src_filename, bak_filename) if src_filename != bak_filename
  end

  def compress_image(from, to)
    orig_size = 0
    comp_size = 0

    nuvo_image do |process|
      image = process.read(from)
      jpeg = process.lossy(image, to, format: :jpeg, quality: :high)

      orig_size = image.size
      comp_size = jpeg.size
    end

    [orig_size, comp_size]
  end

  def copy_file_to_dests(from, dests)
    return if config.dry_run

    dests.each do |fname|
      FileUtils.mkdir_p(File.dirname(fname))
      FileUtils.cp(from, fname)
    end
  end
end
