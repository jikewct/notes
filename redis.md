# redis


## redis

redis支持两种协议RESP和inline，其中inline是支持telnet的协议，RESP是
常规的客户端协议。

### RESP-request

*1\r\n$4\r\nping\r\n
*3\r\n$3\r\nset\r\n$3foo\r\n$3bar\r\n
*2\r\n$3\r\nget\r\n$3foo\r\n

### RESP-reply

For Simple Strings the first byte of the reply is "+"
For Errors the first byte of the reply is "-"
For Integers the first byte of the reply is ":"
For Bulk Strings the first byte of the reply is "$"
For Arrays the first byte of the reply is "*"



## redis 结构

evloop:
+r--> readQueryFromClient
+w--> sendReplyToClient

readQueryFromClient:
read
processInputBuffer:
    processXXBuffer:
        c->multibulklen
        c->bulklen
        c->querybuf
        c->argv
        小结：每个input最后会被放到了argv数组中，转换成human-readable。
    processCommand:
        lookupCommand:
        check...
        call(c,REDIS_CALL_FULL):
           feed monitors
           c->cmd->proc(c)//DEBUG版本会打印每个命令的执行时间
           propagate

commands：
总共158个命令，执行proc

objects:

是一个紧凑的struct，保存了type，encoding，refcount，以及ptr。

lpush:
检查
创建if needed
add reply(listTypeLength(lobj))
signalModifiedKey: 如果key被watch，则该客户端的next exec将失败
notifyKeyspaceEvent: 通知keyspace更改(subscriber将收到通知）
server.dirty += pushed; dirty server

  
## redis-rocksdb


### 基本理念

GET:
got = get (k v) from redis
if (got) return v;
else return get (k v) from rocksdb;

SET:
set (k v) in redis
set (k v) in rocksdb


### 总体设计

- 能不能直接使用nemo引擎？或者我们实现一个类似于nemo的引擎？


### redis-rocksdb-list


#### list commands

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

#### 有关ttl的命令

expire key ttl
expireat key timestamp

#### list相关命令执行流程




