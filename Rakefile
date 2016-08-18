require 'jimson'
require 'facter'
require 'rake'
require_relative 'lib/progress_db'
require_relative 'lib/jpeg_recompress'

namespace :jpeg_recompress do
  task :start, [:dry_run, :src_dir, :dest_dir, :tmp, :thread_count] do |t, args|
    dry_run = args.fetch(:dry_run, true)
    src_dir = args[:src_dir].to_s
    dest_dir = args.fetch(:dest_dir, src_dir).to_s
    tmp_dir = args.fetch(:tmp_dir, '/tmp').to_s
    thread_count = args.fetch(:thread_count, Facter.value('processors')['count']).to_i

    if dry_run == false || dry_run.to_s.downcase == 'wet'
      STDERR.puts('WARNINIG! wet run. type wet')
      type = STDIN.readline.delete("\n")
      unless type.downcase == 'wet'
        STDERR.puts('invaid type')
        exit(1)
      end
    end

    unless File.directory?(src_dir)
      STDERR.puts('invalid src dir')
      exit(1)
    end

    unless File.directory?(dest_dir)
      STDERR.puts('invalid dest dir')
      exit(1)
    end

    unless File.directory?(tmp_dir)
      STDERR.puts('invalid tmp dir')
      exit(1)
    end

    JpegRecompress.new.run(dry_run,
                           File.expand_path(src_dir),
                           File.expand_path(dest_dir),
                           File.expand_path(tmp_dir),
                           thread_count)
  end

  task :status do
    begin
      client = Jimson::Client.new("http://0.0.0.0:8999")
      puts(client.status)
    rescue StandardError
      STDERR.puts('jpeg_recompress not start')
    end
  end

  task :stop do
    begin
      client = Jimson::Client.new("http://0.0.0.0:8999")
      client.stop
      sleep(3)
    rescue StandardError
      STDERR.puts('jpeg_recompress not start')
    end
  end

  task :clean do
    begin
      client = Jimson::Client.new("http://0.0.0.0:8999")
      client.ping
      STDERR.puts('jpeg recompress run')
      exit(1)
    rescue StandardError
      ProgressDb.new.clean
      puts('Clean OK')
    end
  end
end