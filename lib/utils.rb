module Utils
  class << self
    def traversal_dir(dir, after, before)
      Enumerator.new do |y|
        dirs = [[dir, File.stat(dir)]]

        until dirs.empty?
          dirs.sort_by! { |d| d.last.ino }
          current_entry = dirs.pop

          entries = Dir.entries(current_entry.first)
                       .select { |entry| !['.', '..'].include?(entry) }
                       .map { |entry| File.join(current_entry.first, entry) }
                       .map do |entry|
                         begin
                           [entry, File.stat(entry)]
                         rescue StandardError => e
                           $logger.error e
                           nil
                         end
                       end

          entries.compact.each do |entry|
            path, stat = entry

            if stat.directory?
              dirs.push(entry)
              next
            end

            if ['.jpg', '.jpeg'].include?(File.extname(path).downcase) && stat.ctime.between?(after, before)
              y << entry
            end
          end
        end
      end
    end

    def print_skip_or_dot(skip)
      prog_char = skip ? 'S'.colorize(:blue) : '.'.colorize(:green)
      $stdout.print prog_char
    end

    def print_fail
      $stdout.print('F'.colorize(:red))
    end
  end
end
