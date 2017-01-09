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
SemanticLogger.add_appender(appender: :bugsnag, level: :error)
SemanticLogger.add_appender(io: $stderr, formatter: :color)
logger = SemanticLogger['jpeg-recompress']
$logger = logger

check_config_dirs = lambda do |config|
  unless config.valid_src_dir?
    logger.error 'invalid src dir'
    exit(1)
  end

  unless config.valid_dest_dirs?
    logger.error 'invalid dest dir'
    exit(1)
  end

  unless config.valid_tmp_dir?
    logger.error 'invalid tmp dir'
    exit(1)
  end

  unless config.valid_bak_dir?
    logger.error 'invalid bak dir'
    exit(1)
  end
end

read_config_and_check = lambda do
  config = Config.new('config.yml')
  config.dest_dirs.each { |d| FileUtils.mkdir_p(d) }
  FileUtils.mkdir_p(config.bak_dir) if config.bak_dir

  check_config_dirs.call config
  logger.info config

  config
end

task :recompress do
  config = read_config_and_check.call
  JpegRecompress.new(config).run :process
end

task :compare do
  config = read_config_and_check.call
  JpegCompare.new(config).run :process
end

task :find do
  config = read_config_and_check.call
  JpegRecompress.new(config).run :find
end

task :status do
  begin
    client = Jimson::Client.new('http://0.0.0.0:8998')
    logger.info client.status
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
    logger.warn 'Nothing to stop'
  rescue StandardError => e
    logger.error e
  end
end

task :clean do
  begin
    client = Jimson::Client.new('http://0.0.0.0:8998')
    client.ping
    logger.warn 'Still processing...'
    exit(1)
  rescue Errno::ECONNREFUSED
    RecompressDb.new.clean
    logger.info 'Clean OK'
  rescue StandardError => e
    logger.error e
  end
end
