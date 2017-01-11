require_relative 'jpeg_process'

class JpegCompare < JpegProcess
  extend Jimson::Handler

  def initialize(config)
    super(config, Jimson::Server.new(self, port: 8998), CompareDb.new)
  end

  def status
    elapsed_time = (complete_time || Time.now) - start_time
    result = database.compare_status
    count = result[:count]
    compare_count = result[:compare_count]
    match_count = result[:match_count]

    percent = compare_count.to_f / count.to_f * 100
    percent = 0.0 if percent.nan?

    str = "\n#{config}\n"
    str << "start #{start_time}"
    str << ", complete #{complete_time}" if complete_time
    str << ", elapsed #{elsapsed_time_str(elapsed_time)}"
    str << "\n"
    str << "compare #{compare_count}/#{count}(#{format('%.2f', percent)}%)"
    str << ", match #{match_count}"
    str << ", unmatch #{compare_count - match_count}"
    str
  end

  def process_files(rows)
    results = Parallel.map(rows, in_threads: config.thread_count) do |row|
      return nil unless config.dst_dir

      src_filepath = row[:filename]
      return nil unless File.exist?(src_filepath)

      relative_filepath = Pathname.new(src_filepath).relative_path_from(Pathname.new(config.src_dir))
      dst_filepath = File.join(config.dst_dir, relative_filepath)
      ssim = 0

      if File.exist?(src_filepath) || File.exist?(dst_filepath)
        begin
          nuvo_image do |process|
            image1 = process.read(src_filepath)
            image2 = process.read(dst_filepath)

            ssim = process.compare(image1, image2)
          end
        rescue StandardError => e
          logger.error e
          ssim = 0
        ensure
          prog_char = ssim > 0.8 ? '.'.colorize(:green) : 'F'.colorize(:red)
          $stdout.print prog_char
        end
      end

      { id: row[:id], ssim: ssim }
    end

    print(' '.colorize(:white).on_white)

    database.transaction do
      results.compact.each do |result|
        database.update result
      end
    end
  end
end
