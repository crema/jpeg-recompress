# jpeg-recompress

## Requirement

### nuvo-image

https://github.com/crema/nuvo-image#requirement

### libsqlite3-dev

```bash
sudo apt-get install libsqlite3-dev
```


## Usage

```bash
bundle install
bundle exec rake jpeg_recompress:start

bundle exec rake jpeg_recompress:status

bundle exec rake jpeg_recompress:stop
```

## config

config.yml

```yaml
jpeg_recompress:
  dry_run: false
  src_dir: /home/ubuntu/다운로드/assets
  dest_dir: /home/ubuntu/다운로드/converted
  thread_count: 0
  tmp_dir: /tmp
  before: 2016-08-20
  after: 2000-01-01
```
