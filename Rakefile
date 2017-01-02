require 'jimson'
require 'facter'
require 'rake'
require_relative 'lib/jpeg_recompress'
require_relative 'lib/jpeg_compare'

def check_config_dirs(config)
  unless config.valid_src_dir?
    STDERR.puts('invalid src dir')
    exit(1)
  end

  unless config.valid_dest_dir?
    STDERR.puts('invalid dest dir')
    exit(1)
  end

  unless config.valid_tmp_dir?
    STDERR.puts('invalid tmp dir')
    exit(1)
  end

  unless config.valid_bak_dir?
    STDERR.puts('invalid bak dir')
    exit(1)
  end
end

namespace :jpeg_recompress do
  task :start do
    config = Config.new('config.yml')

    FileUtils.mkdir_p(config.dest_dir) unless Dir.exist?(config.dest_dir)

    check_config_dirs(config)
    puts config

    JpegRecompress.new(config).run
  end

  task :status do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8998')
      puts(client.status)
    rescue StandardError
      STDERR.puts('jpeg_recompress not start')
    end
  end

  task :stop do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8998')
      client.stop
      sleep(3)
    rescue StandardError
      STDERR.puts('jpeg_recompress not start')
    end
  end

  task :clean do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8998')
      client.ping
      STDERR.puts('jpeg recompress run')
      exit(1)
    rescue StandardError
      RecompressDb.new.clean
      puts('Clean OK')
    end
  end
end

namespace :jpeg_compare do
  task :start do
    config = Config.new('config.yml')

    FileUtils.mkdir_p(config.dest_dir) unless Dir.exist?(config.dest_dir)

    check_config_dirs(config)
    puts config

    JpegCompare.new(config).run
  end

  task :status do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8999')
      puts(client.status)
    rescue StandardError
      STDERR.puts('jpeg_compare not start')
    end
  end

  task :stop do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8999')
      client.stop
      sleep(3)
    rescue StandardError
      STDERR.puts('jpeg_compare not start')
    end
  end

  task :clean do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8999')
      client.ping
      STDERR.puts('jpeg_compare run')
      exit(1)
    rescue StandardError
      RecompressDb.new.clean
      puts('Clean OK')
    end
  end
end
