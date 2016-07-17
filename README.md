# jpeg-recompress

## Requirement

### nuvo-image
https://github.com/crema/nuvo-image#requirement

### libsqlite3-dev

```
sudo apt-get install libsqlite3-dev
```


## Usage

```
bundle install
bundle exec ruby jpeg-recompress.rb dest=/mnt/1 thread=4 db=recompress.db dry=true before=2017-07-17
```

- dest= 재압축할 경로 
- thread= 쓰레드 개수. 기본으로 4 를 사용한다 
- db= 재압축 상황을 기록할 파일. 입력하지 않으면 recompress.db 를 기본으로 사용한다 
- dry= 값을 넣으면 실제로 덥어쓰지 않는 dry-run을 실행한다 
- batch= 배치 사이즈, 기본값 5000
- quality= 목표 ssim 값. 기본값 0.966
- before= 해당 시간보다 오래된 파일만 적용. 기본값 now 