require 'aws-sdk'
require 'bugsnag'
require 'byebug'
require 'facter'
require 'jimson'
require 'rake'
require 'semantic_logger'
require_relative 'lib/jpeg_compare'
require_relative 'lib/jpeg_recompress'

Bugsnag.configure do |config|
  config.api_key = ENV['JPEG_RECOMPRESS_BUGSNAG_API_KEY']
  config.release_stage = ENV['RAILS_ENV'] || 'development'
end
SemanticLogger.add_appender(appender: :bugsnag)
SemanticLogger.add_appender(io: STDERR, formatter: :color)
logger = SemanticLogger['jpeg-recompress']

def check_config_dirs(config)
  unless config.valid_src_dir?
    logger.error('invalid src dir')
    exit(1)
  end

  unless config.valid_dest_dirs?
    logger.error('invalid dest dir')
    exit(1)
  end

  unless config.valid_tmp_dir?
    logger.error('invalid tmp dir')
    exit(1)
  end

  unless config.valid_bak_dir?
    logger.error('invalid bak dir')
    exit(1)
  end
end

def read_config_and_check
  config = Config.new('config.yml')
  config.dest_dirs.each { |d| FileUtils.mkdir_p(d) }
  FileUtils.mkdir_p(config.bak_dir) if config.bak_dir

  check_config_dirs(config)
  puts config

  config
end

namespace :jpeg_recompress do
  task :start do
    config = read_config_and_check
    JpegRecompress.new(config).run
  end

  task :status do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8998')
      puts(client.status)
    rescue StandardError => e
      logger.error e
    end
  end

  task :stop do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8998')
      client.stop
      sleep(3)
    rescue Errno::ECONNREFUSED
      logger.warn 'jpeg_recompress is not running'
    rescue StandardError => e
      logger.error e
    end
  end

  task :clean do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8998')
      client.ping
      logger.warn 'jpeg_recompress is running'
      exit(1)
    rescue Errno::ECONNREFUSED
      RecompressDb.new.clean
      puts('Clean OK')
    rescue StandardError => e
      logger.error e
    end
  end
end

namespace :jpeg_compare do
  task :start do
    config = read_config_and_check
    JpegCompare.new(config).run
  end

  task :status do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8999')
      puts(client.status)
    rescue StandardError => e
      logger.error e
    end
  end

  task :stop do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8999')
      client.stop
      sleep(3)
    rescue Errno::ECONNREFUSED
      logger.warn 'jpeg_compare is not running'
    rescue StandardError => e
      logger.error e
    end
  end

  task :clean do
    begin
      client = Jimson::Client.new('http://0.0.0.0:8999')
      client.ping
      logger.warn 'jpeg_compare is running'
      exit(1)
    rescue Errno::ECONNREFUSED
      RecompressDb.new.clean
      puts('Clean OK')
    rescue StandardError => e
      logger.error e
    end
  end
end
