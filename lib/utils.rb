module Utils
  class << self
    def traversal_dir(dir, after, before)
      Enumerator.new do |y|
        dirs = [[dir, File.stat(dir)]]

        until dirs.empty?
          dirs.sort_by! { |d| d.last.ino }
          cur_dir = dirs.pop.first

          entries = Dir.entries(cur_dir)
                       .select { |entry| !['.', '..'].include?(entry) }
                       .map do |entry|
                         begin
                           fullpath = File.join(cur_dir, entry)
                           [fullpath, File.stat(fullpath)]
                         rescue StandardError => e
                           $logger.error e
                           nil
                         end
                       end
          dir_entries, file_entries = entries.compact.partition { |entry| entry.last.directory? }
          dirs += dir_entries
          file_entries.each { |entry| y << entry if entry.last.ctime.between?(after, before) }
        end
      end
    end

    def print_dot_or_skip(compressed)
      prog_char = compressed ? '.'.colorize(:green) : 'S'.colorize(:blue)
      $stdout.print prog_char
    end

    def print_fail
      $stdout.print('F'.colorize(:red))
    end
  end
end
