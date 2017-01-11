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
bundle exec rake find
bundle exec rake recompress
bundle exec rake status
bundle exec rake stop
```

## config

config.yml

```yaml
jpeg_recompress:
  dry_run: true
  src_dir: /mnt/1/crema-rails-assets
  dst_dir: /mnt/2/crema-rails-assets
  batch_count: 1000
  tmp_dir: /run/shm
  active_start: '02:00' # in 24-hours
  active_for: 8 # hours
```
