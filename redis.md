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




# lua


eval <script> numkeys key1 key2 ... arg1 arg2 ...
evalsha <sha> numkeys key1 key2 ... arg1 arg2 ...

server.lua
server.lua_client
server.repl_scriptcache_fifo 
server.lua_random_dirty = 0;
server.lua_write_dirty = 0;
server.lua_replicate_commands = server.lua_always_replicate_commands;
server.lua_multi_emitted = 0;
server.lua_repl = PROPAGATE_AOF|PROPAGATE_REPL;

## 接口

redis.log
redis.call
redis.pcall
redis.repl_commands
redis.set_repl
redis.sha1hex
redis.debug
redis.error_reply
redis.status_reply

## lua与复制

- eval将被完整地复制到slave中执行
- evalsha在master确认slave确认已经含有script的情况下才会执行evasha，否则将会转换成eval执行

## lua与aof

- eval将被原样记录到AOF中
- evalsha第一次（或者rewrite之后第一次）转换成eval执行，后续直接记录evalsha
- rewriteaof之后，aof中不再存有scriptload，evalsha等命令

## lua与aof-binlog

- lua的复制和AOF是通过multi和exec做的？

## lua与aof-binlog合并

- 由于aof-binlog如果不指定replicate_commands，默认是replicate_scripts，这样的合并的意义不大


# 超时

- 超时后master通过DEL命令删除slave过期key、slave从来不主动删除过期key，从而保证数据一致性
- 3.2之后slave增加了logic clock功能、除了等待master的DEL命令，slave本身也对读取命令计算超时
- lua脚本的时间静止 server.lua_start_time
- aof-binlog中删除区分DEL_BY_CLIENT, DEL_BY_EXPIRE, DEL_BY_EVICT，因此如果应用有需求不同步EXPIRE信息，这个是可以做到的

参考材料:

- http://arganzheng.life/key-expired-in-redis-slave.html
- https://github.com/antirez/redis/issues/1768
- https://github.com/antirez/redis/issues/187



-----------------
对于redis的更加细节的了解：

- lua客户端是怎么用的？lua的函数和lib是怎么加载进来的？
- client怎么发送结果？output buffer? resetClient?

prepareClientToWrite是个神奇的函数：

调用方式：


|addDeferredMultiBulkLength
|addReplyString
|addReplySds
|addReply
    prepareClientToWrite #fake client(used to load aof), master, handler setup failed --> return C_ERR
 

addReply*分散在各数据结构中，随着call执行，reply将被准备好。

server.clients_pending_write # 等待安装write handler的客户端。
真正安装的时候，redis将先尝试写reply，只有一次evloop写不完所有reply才会真的安装write handler

客户端在before sleep尝试将reply发送出去，但是也不会超过64K

client->buf[PROTO_REPLY_CHUNK_BYTES] # 默认每个client都有一个16K的缓存。100W连接，直接耗费16G内存，所以说连接多了，耗费内存
client->bufpos
client->sentlen

beforeSleep
    handleClientsWithPendingWrites

- pub/sub在代码中怎么实现的？

client->pubsub_channels: {channel:NULL}
server->pubsub_channels: {channel: [client]}

真的没有意思！

```
        !(c->flags & CLIENT_SLAVE) &&    /* no timeout for slaves */
        !(c->flags & CLIENT_MASTER) &&   /* no timeout for masters */
        !(c->flags & CLIENT_BLOCKED) &&  /* no timeout for BLPOP */
        !(c->flags & CLIENT_PUBSUB) &&   /* no timeout for Pub/Sub clients */

    /* Only allow SUBSCRIBE and UNSUBSCRIBE in the context of Pub/Sub */
    if (c->flags & CLIENT_PUBSUB &&
        c->cmd->proc != pingCommand &&
        c->cmd->proc != subscribeCommand &&
        c->cmd->proc != unsubscribeCommand &&
        c->cmd->proc != psubscribeCommand &&
        c->cmd->proc != punsubscribeCommand) {
        addReplyError(c,"only (P)SUBSCRIBE / (P)UNSUBSCRIBE / PING / QUIT allowed in this context");
        return C_OK;
    }

    另外ping xx 在pub/sub 上下文的回复与正常的不一样！
```

----------
CLIENT 命令

```
CLIENT KILL [ip:port] [ID client-id] [TYPE normal|master|slave|pubsub] [ADDR ip:port] [SKIPME yes/no]
CLIENT PAUSE timeout    # 停止处理客户端请求
CLIENT REPLY ON|OFF|SKIP    # 在某些（比如缓存）场景下，REPLY是一定被抛弃的，此时可以设置REPLY模式为NO节省时间和带宽。

CLIENT LIST
CLIENT SETNAME connection-name
CLIENT GETNAME
```
----------
loading过程有点特殊：
- slave可以执行lua写命令（正常只有master客户端可以）


-----------

关于psync2


----------
关于block operation

----------
关于monitor

----------
关于client unlink, reset, free, freeasync 

server->current_client
server->clients
client->querybuf
client->pending_querybuf

freeClient:
    如果是master，则-->cached_master

    否则

unlinkClient:
    close sockets, remove IO handler, remove references

freeClientAsync:qa

-------



## 关于复制的详细分析


1. 数据结构
----
server.master{flags,reploff,authenticated,replrunid} # 如果reploff为-1，则REDIS_PRE_PSYNC
server.cached_master{replrunid}     # 有cached_master: PSYNC cached_master.replrunid cached_master.reploff+1； 没有cached_master就主动fullsync: PSYNC ? -1
server.master_host 是否是slave的标记
server.master_repl_offset 从master中继承而来，作为master期间，主动递增该offset
server.repl_transfer_s  M--S之间的socket
server.repl_transfer_fd
server.repl_transfer_tmpfile
server.repl_transfer_lastio
server.repl_state
server.repl_master_runid
server.repl_master_initial_offset
server.repl_transfer_size 
server.repl_transfer_read
server.repl_transfer_last_fsync_off
server.slaves
server.slaveseldb
server.rdb_pipe_read_result_from_child  # 哇塞，为了可读性真舍得！
server.rdb_pipe_write_result_to_parent


slave.replstate
slave.repldbfd      # rdb fd
slave.repldboff     # rdb file offset
slave.repldbsize    # rdb size
slave.flags
slave.psync_initial_offset  # master offset when FULLRESYNC started
slave.replpreamble

2. 事件流转
----

a) POV REDIS_SLAVE:
----

NONE
CONNECT
CONNECTING --> (RW, syncWithMaster)

/* --- Handshake states, must be ordered --- */

RECEIVE_PONG --> (R, syncWithMaster) # 已经连接上了，不在需要写事件；握手阶段slave同步握手，无法处理其他请求
SEND_AUTH
RECEIVE_AUTH
SEND_PORT
RECEIVE_PORT
SEND_CAPA
RECEIVE_CAPA
SEND_PSYNC
RECEIVE_PSYNC -->  +FULLRESYNC <runid> <offset> --> ; +CONTINUE (R, readQueryFromClient; W, sendReplyToClient); -ERR --> (R, readSyncBulkPayload)

/* --- End of handshake states --- */

TRANSFER  # \n hearbeat; $EOF <runid>; $len <bulk>; 接受全量数据之后 --> ()
CONNECTED


readSyncBulkPayload收尾工作
----
signalFlushedDb # 通知watched keys已经变更
emptyDb # 为了防止清空数据导致slave假死，emptyDb传入和一个发送"\n"的cb，用于保活M S链路
rdbLoad # 为了防止rdbLoad导致slave假死，rdbLoad传入了一个复杂的cb（计算checksum，每2M更新server.unixtime, 向master发送\n, 处理少量ev(获取info)）
server.master创建  # 创建master客户端
stopAppendOnly,startAppendOnly # 每次FULLRESYNC都会触发bgaofrewrite.

b) POV REDIS_MASTER
----

WAIT_BGSAVE_START   # 需要FULLRESYNC时，标记slave为WAIT_BGSAVE_START；通常BGSAVE在BGSAVE中进行
WAIT_BGSAVE_END     # 已经开启了BGSAVE，等待完成:disk,BGSAVE完成；diskless, 有子进程则WAIT_END
SEND_BULK  --> (W,sendBulkToSlave)   # repl类型为DISK时，BGSAVE_END之后，状态转换为SEND_BULK
ONLINE     --> (W,sendReplyToClient)  # diskless在子进程退出之后；disk sendBulkToSlave之后


diskless 的进程间通信：
<len> <slave[0].id> <slave[0].error> ...

### 问题

- slave握手阶段无法处理请求，那么sentinel发送的info是不是也无法处理，会不会进入+sdown状态？
- redis复制协议能不能向前兼容
- pipe W端写入时如果R端没有读取，能不能写入？如果能写入，但是W进程退出了，R进程还能读到么？
- diskless传递会父进程的信息有啥用？
- diskless啥时候删的W事件？
- rdbsave的时候slave的W事件？
- 为什么WAIT_BGSAVE_END状态中，feedReplication的数据不会丢失，并且不会发送给slave？
- 为什么PSYNC成功，能够正确地把增量数据发送给slave

### 链式复制

- 无法向middle PSYNC如果当前middle与master的链路未连接

### 碎碎念

- getLongFromObjectOrReply 工具函数，解析数字的时候也直接回复
- 下游slaves随着上游master的改变，切换数据源
- 为什么redis可以如此紧凑地实现业务逻辑???: 不处理oom（虽然不处理OOM，但是处理系统调用错误）
- 不管同步还是异步，上来先把fd设置为nonblocking基本都是没错的
- 由于Master可能需要很久才能把RDB文件准备好，因此slave发送了PSYNC后master发送RDB之前，master通过向slave发送newline保活。
- redis所有的回复都存在了client->reply列表
- +FULLRESYNC <master.runid> <master.master_repl_offset ? +1> （无backlog +1 )
- 在slave中含有
- 由于master收到PSYNC请求之后，如果配置是disless repl，并且delay比较长，那么master将发送\n保活
- 由于master收到PSYNC请求之后，如果当前有BGSAVE正在进行但是没法客户端保存diff，那么需要等待BGSAVE下次schedule时间比较长，那么master将发送\n保活
- 在rdbsave进行时，避免进行dictResize，避免对COW不友好
- 如果psync;ping 通过pipeline进行，那么sync可能收到PONG回复 NONONO 收不到，只要客户端进入复制状态就不会在收到reply了（因为master WAIT_BGSAVE_START会进入假死保活状态，但是没有删除读写事件，因此sync命令会收到PONG）



--------------


## 关于propagate的详细分析


call(c, flags):

- processCommand
- lua redis.call flags为REDIS_CALL_SLOWLOG | REDIS_CALL_STATS（不需要propagate)


propagate:

- execCommandPropagateMulti
- pub/sub
- call & dirty
- lua script load / evasha --> eva


replicationFeedSlaves:

- propagate
- expire && evicted (propagateExpire)
- replconf getack 从slave中尽快获取ack
- replicationCron中对slave定期PING

feedAppendOnlyFile:

- propagate
- expire && evicted (propagateExpire)


--------------------

## 关于pub/sub的详细分析

- pub/sub 会被复制到slave，但是不会持久化到aof中

### 问题

- 在lua脚本里头的pub/sub会不会复制到slave？





