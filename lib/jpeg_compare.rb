require_relative 'compare_db'
require_relative 'jpeg_process'

class JpegCompare < JpegProcess
  extend Jimson::Handler

  def initialize(config)
    super(config, Jimson::Server.new(self, port: 8999), CompareDb.new)
  end

  def status
    elapsed_time = if complete_time
                     complete_time - start_time
                   else
                     Time.now - start_time
                   end

    count, compare_count, match_count = database.status.map(&:to_i)

    percent = compare_count.to_f / count.to_f * 100
    percent = 0.0 if percent.nan?

    str = ''
    str << config.to_s
    str << "\n"
    str << "start #{start_time}"
    str << ", complete #{complete_time}" if complete_time
    str << ", elapsed #{elsapsed_time_str(elapsed_time)}"
    str << "\n"

    str << "compare #{compare_count}/#{count}(#{format('%.2f', percent)}%)"
    str << ", match #{match_count}"
    str << ", unmatch #{compare_count - match_count}"

    str
  end

  def process_files(filenames)
    results = Parallel.map(filenames, in_threads: config.thread_count) do |src_filename|
      filename = Pathname.new(src_filename).relative_path_from(Pathname.new(config.src_dir))
      dest_filename = File.join(config.dest_dir, filename)
      ssim = 0

      if File.exist?(src_filename) || File.exist?(dest_filename)
        begin
          nuvo_image do |process|
            image1 = process.read(src_filename)
            image2 = process.read(dest_filename)

            ssim = process.compare(image1, image2)
          end
        rescue StandardError => e
          logger.error e
          ssim = 0
        ensure
          prog_char = ssim > 0.8 ? '.'.colorize(:green) : 'F'.colorize(:red)
          STDOUT.print prog_char
        end
      end
      [src_filename, ssim]
    end

    print(' '.colorize(:white).on_white)
    database.transaction do
      results.each do |result|
        database.set_ssim(result.first, result.last)
      end
    end
  end
end
