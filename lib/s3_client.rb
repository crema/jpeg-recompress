class S3Client
  def initialize
    @s3_client = Aws::S3::Client.new(region: 'ap-northeast-2')
    @bucket = "crema-#{ENV['RAILS_ENV']}"
  end

  def put_object(full_path, key, retries: 3, sleep_time: 5)
    key = self.class.normalize key
    File.open(full_path, 'rb') do |file|
      s3_client.put_object(bucket: bucket, key: key, body: file)
    end
  rescue StandardError
    raise unless retries.positive?

    sleep sleep_time
    retries -= 1
    retry
  end

  def self.normalize(path)
    path.to_s.sub(%r{^/+}, '').gsub(%r{/+}, '/')
  end

  private

  attr_reader :s3_client, :bucket
end
