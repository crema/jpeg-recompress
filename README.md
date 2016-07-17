# jpeg-recompress

## Requirement

### nuvo-image 요구 사항 확인
https://github.com/crema/nuvo-image#requirement

### libsqlite3-dev

```
sudo apt-get install libsqlite3-dev
```


## Usage

```
bundle install
bundle exec ruby jpeg-recompress.rb dest=/mnt/1 thread=4 db=recompress.db dry=true
```

- dest= 재압축할 경로 
- thread= 쓰레드 개수. 기본으로 4 를 사용한다 
- db= 재압축 상황을 기록할 파일. 입력하지 않으면 recompress.db 를 기본으로 사용한다 
- dry= 값을 넣으면 실제로 덥어쓰지 않는 dry-run을 실행한다 
