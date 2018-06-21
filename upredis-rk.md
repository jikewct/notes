# upredis-rocksdb

upredis冷热分离项目

## 需求

用户系统最初提出，暂时可能不会在系统中推广使用。

## 时间计划


## 

# redis-rocksdb


## 基本理念

GET:
got = get (k v) from redis
if (got) return v;
else return get (k v) from rocksdb;

SET:
set (k v) in redis
set (k v) in rocksdb


## 总体设计

- 能不能直接使用nemo引擎？或者我们实现一个类似于nemo的引擎？


## redis-rocksdb-list


### list commands

BLPOP key [key ...] timeout
BRPOP key [key ...] timeout
BRPOPLPUSH source destination timeout
LINDEX key index
LINSERT key BEFORE|AFTER pivot value
LLEN key
LPOP key
LPUSH key value [value ...]
LPUSHX key value
LRANGE key start stop
LREM key count value
LSET key index value
LTRIM key start stop
RPOP key
RPOPLPUSH source destination
RPUSH key value [value ...]
RPUSHX key value

### 有关ttl的命令

expire key ttl
expireat key timestamp

### list相关命令执行流程


