require_relative 'jpeg_process'
require_relative 's3_client'

class JpegRecompress < JpegProcess
  extend Jimson::Handler

  def initialize(config)
    super(config, Jimson::Server.new(self, host: 'localhost', port: 8998), RecompressDb.new)
    @s3_client = S3Client.new
  end

  def status
    elapsed_time = (complete_time || Time.now) - start_time
    result = database.recomp_status
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
      src_filepath = row[:filename]
      return nil unless File.exist?(src_filepath)

      relative_filepath = Pathname.new(src_filepath).relative_path_from(Pathname.new(config.src_dir))
      orig_size = row[:orig_size]
      comp_size = orig_size
      tmp_filepath = File.join(config.tmp_dir, "#{tmp_str}#{tmp_count.increment}.jpg")
      compressed = false

      begin
        if row[:is_jpeg] && row[:ctime] < config.upload_after
          orig_size, comp_size = compress_image(src_filepath, tmp_filepath)
          compressed = comp_size < orig_size
        else
          FileUtils.cp(src_filepath, tmp_filepath)
        end

        upload_to_s3(tmp_filepath, relative_filepath)
      rescue StandardError => e
        # logger.error "fail: #{src_filepath}", e
        comp_size = -1
      ensure
        if !config.dry_run && config.dst_dir && (compressed || config.src_dir != config.dst_dir)
          dst_filepath = File.join(config.dst_dir, relative_filepath)
          copy_file_to_dst(tmp_filepath, dst_filepath)
        end

        File.delete(tmp_filepath) if File.exist?(tmp_filepath)

        if comp_size == -1
          Utils.print_fail
        else
          Utils.print_dot_or_skip(compressed)
        end
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

  def upload_to_s3(full_path, key)
    @s3_client.put_object(full_path, key) unless config.dry_run
  end

  def copy_file_to_dst(from, dst)
    return unless File.exist?(from)

    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.cp(from, dst)
  end
end
