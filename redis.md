# Redis

## 协议

redis支持两种协议RESP和inline，其中inline是支持telnet的协议，RESP是
常规的客户端协议。

### RESP-request

```
*1\r\n$4\r\nping\r\n
*3\r\n$3\r\nset\r\n$3foo\r\n$3bar\r\n
*2\r\n$3\r\nget\r\n$3foo\r\n
```

### RESP-reply

```
For Simple Strings the first byte of the reply is "+"
For Errors the first byte of the reply is "-"
For Integers the first byte of the reply is ":"
For Bulk Strings the first byte of the reply is "$"
For Arrays the first byte of the reply is "*"
```

## 事件循环


安装WRITE事件：

- server.clients_pending_write # 等待安装write handler的客户端。
- `addReply*`分散在数据结构中，随着命令执行reply被准备好。
- prepareClientToWrite: 准备安装WRITE事件; 决定需要拷贝reply到buffer
- 客户端在before sleep尝试将reply发送出去(不超过64K)，只有evloop写不完所有reply才会安装write handler。

## Expire

- slave不会因为超时修改keyspace，master expire时通过广播DEL命令保证超时
- type, ttl命令不会更新lru

### `lookupKey*`

```
lookupKey //从expire表中查找key，不考虑超时；
lookupKeyReadWithFlags //为读操作查找key，副作用：超时;更新hits/misses;更新lru
expireIfNeeded  //返回是否超时，如果master则从keyspace删除，如果slave则不删除
```


### redis-3.2改进

为了保持master-slave之间对于超时的一致性，超时key的剔除是master主导的: 当master
上的key过期后，master向slave发送DEL实现过期key的删除。

因此即使master上的key已经超时，slave无法也无法主动超时key, 所以可能出现GET在
slave上返回stale data，但是在master上返回nil。这对于读写分离来讲是一个比较严重的
问题。

所以在3.2中，修改lookupKeyRead：当前redis为slave（并且不是master客户端）可以返回
NULL，但是实际上不会对keyspace做修改。





### 相关issues

[Improve expire consistency on slaves ](https://github.com/antirez/redis/issues/1768)
[Better read-only behavior for expired keys in slaves.](https://github.com/antirez/redis/commit/06e76bc3e22dd72a30a8a614d367246b03ff1312)

## redisObj

- EMBSTR 为了减少sds头占用的内存，对于44B之内的String新增EMBSTR编码


### 相关issues

[关于lru，lfu value error](https://github.com/antirez/redis/pull/5011)
  


## lua


```
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
```

### 接口

redis.log
redis.call
redis.pcall
redis.repl_commands
redis.set_repl
redis.sha1hex
redis.debug
redis.error_reply
redis.status_reply

### lua与复制

- eval将被完整地复制到slave中执行
- evalsha在master确认slave确认已经含有script的情况下才会执行evasha，否则将会转换成eval执行

### lua与aof

- eval将被原样记录到AOF中
- evalsha第一次（或者rewrite之后第一次）转换成eval执行，后续直接记录evalsha
- rewriteaof之后，aof中不再存有scriptload，evalsha等命令

### lua与aof-binlog

- lua的复制和AOF是通过multi和exec做的？

### lua与aof-binlog合并

- 由于aof-binlog如果不指定replicate_commands，默认是replicate_scripts，这样的合并的意义不大


### 超时

- 超时后master通过DEL命令删除slave过期key、slave从来不主动删除过期key，从而保证数据一致性
- 3.2之后slave增加了logic clock功能、除了等待master的DEL命令，slave本身也对读取命令计算超时
- lua脚本的时间静止 server.lua_start_time
- aof-binlog中删除区分DEL_BY_CLIENT, DEL_BY_EXPIRE, DEL_BY_EVICT，因此如果应用有需求不同步EXPIRE信息，这个是可以做到的

参考材料:

- http://arganzheng.life/key-expired-in-redis-slave.html
- https://github.com/antirez/redis/issues/1768
- https://github.com/antirez/redis/issues/187


## pub/sub

- pub/sub 会被复制到slave，但是不会持久化到aof中
- 在lua脚本里头的pub/sub会不会复制到slave？

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


- pub/sub在代码中怎么实现的？


CLIENT 命令

```
CLIENT KILL [ip:port] [ID client-id] [TYPE normal|master|slave|pubsub] [ADDR ip:port] [SKIPME yes/no]
CLIENT PAUSE timeout    # 停止处理客户端请求
CLIENT REPLY ON|OFF|SKIP    # 在某些（比如缓存）场景下，REPLY是一定被抛弃的，此时可以设置REPLY模式为NO节省时间和带宽。

CLIENT LIST
CLIENT SETNAME connection-name
CLIENT GETNAME
```
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



## 复制

### 数据结构

```
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
server.rdb_pipe_read_result_from_child
server.rdb_pipe_write_result_to_parent


slave.replstate
slave.repldbfd      # rdb fd
slave.repldboff     # rdb file offset
slave.repldbsize    # rdb size
slave.flags
slave.psync_initial_offset  # master offset when FULLRESYNC started
slave.replpreamble
```

### 事件流转

a) POV REDIS_SLAVE:

NONE
CONNECT
CONNECTING --> (RW, syncWithMaster)

```

RECEIVE_PONG --> (R, syncWithMaster) # 已经连接上了，不在需要写事件；握手阶段slave同步握手，无法处理其他请求
SEND_AUTH
RECEIVE_AUTH
SEND_PORT
RECEIVE_PORT
SEND_CAPA
RECEIVE_CAPA
SEND_PSYNC
RECEIVE_PSYNC -->  +FULLRESYNC <runid> <offset> --> ; +CONTINUE (R, readQueryFromClient; W, sendReplyToClient); -ERR --> (R, readSyncBulkPayload)


TRANSFER  # \n hearbeat; $EOF <runid>; $len <bulk>; 接受全量数据之后 --> ()
CONNECTED
```


readSyncBulkPayload收尾工作

signalFlushedDb # 通知watched keys已经变更
emptyDb # 为了防止清空数据导致slave假死，emptyDb传入和一个发送"\n"的cb，用于保活M S链路
rdbLoad # 为了防止rdbLoad导致slave假死，rdbLoad传入了一个复杂的cb（计算checksum，每2M更新server.unixtime, 向master发送\n, 处理少量ev(获取info)）
server.master创建  # 创建master客户端
stopAppendOnly,startAppendOnly # 每次FULLRESYNC都会触发bgaofrewrite.

b) POV REDIS_MASTER

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


### propagate


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

# Hiredis

## 同步

- redisGetReply先发送，后读取，再处理
- processItem返回REDIS_ERR表示停止解析：如果buffer空，reader状态正常；如果解析出错，调`__redisReaderSetError__`设置且通过redisReaderGetReply返回值表示
- redisReply是多态类型，MULTIBULK对应ARRAY，ARRAY中的每个元素又是一个`redisReply*`
- commands采用了printf设计模式

## 异步

总体思路就是hiredis实现读写ev，借用事件库驱动各连接的ev。

## FAQ

- redisContext.err 与 REDIS_REPLY_ERROR的区别

分别对应JCE和JDE，JCE意味着当前redisContext无法继续使用，需要创建新的context；
JDE意味着"-ERR"且链路正常，链路可以继续使用。

目前upredis-api-c无法获取JCE的详细信息。JCE的种类分为:

* **`REDIS_ERR_IO`**: 发生时upredis_open_conn或者replyObject为NULL，可以通过errno获取详细信息
* **`REDIS_ERR_EOF`**: 发生时upredis_get_reply结果为NULL，无法获取信息
* **`REDIS_ERR_PROTOCOL`**: 发生时redis_get_reply结果为NULL，无法获取详细信息
* **`REDIS_ERR_OTHER`**: 发生时upredis_open_conn为NULL，无法获取详细信息

所以应该增加一个JCE相关err信息获取方法。


# Redis版本

upredis基于redis-2.8.23定制开发。开源redis最新stable版为4.0，上一个stable版为3.2。

为描述方便，redis指开源redis。

## redis版本策略

redis版本按照稳定性可以分为development、frozen、release candidate、stable，
每个redis发布版本都会经过以上稳定性变更。

redis源代码分支分为unstable、fork、stable分支。

比如说redis-2.6发布之后，unstable分支将被fork到2.8分支(fork分支)；

fork分支将经历development, frozen, and release candidate三个阶段：

- Development：可以添加（版本计划的）新功能
- Frozen：几乎没有新功能添加（除非是重要紧急的feature或者对稳定性没有影响的feature）
- Release Candidate：只进行bugfix

当fork分支连续若干周没有重大bugfix时，fork分支被标记为stable正式发布GA版。

redis版本号遵循major.minor.patch规则，稳定版的minor为偶数，非稳定为奇数。

以上例子中在GA之前的版本为2.5.x。在fork分支进入RC阶段之后，patch版本号从100开始，也就是
2.5.101表示2.6-RC1。

## redis版本历史

upredis基于redis-2.8.23定制开发，与最新的redis-4.0相差3.0,3.2,4.0三个版本。

### redis-3.0.x

redis-3.0主要发布cluster。

其他重要更新包括WAIT命令实现同步复制和性能优化。

#### cluster

（略）

#### 同步复制

```
WAIT numslaves timeout
```

实现方法：

1. 阻塞调用wait命令的客户端
2. master evloop结束后向所有slave发送 ` REPLCONF GETACK`
3. 收到numslaves数量的回复之后，unblock客户端


#### 主要变动

```
- Redis Cluster: a distributed implementation of a subset of Redis.
- New "embedded string" object encoding
- Much improved LRU approximation algorithm
- WAIT command
- MIGRATE connection caching.
- MIGRATE new options COPY and REPLACE.
- CLIENT PAUSE command.
- BITCOUNT performance improvements
- Redis log format slightly changed for master/slave role
- INCR performance improvements
```

#### 发布历史

```
3.0.7 2016/1/25 MODERATE
3.0.6 2015/12/18    MODERATE
3.0.5 2015/10/15    MODERATE    
3.0.4 2015/9/8  LOW for Redis and Sentinel
3.0.3 2015/7/17 HIGH for Redis because of a security issue.
3.0.2 2015/6/4  LOW for Redis and Cluster, MODERATE for Sentinel
3.0.1 2015/5/5  LOW 
3.0.0 2015/4/1  
3.0-rc6 2015/3/34   HIGH because of bugs related to Redis Custer and replication
3.0-rc5 2015/3/20   Moderate for Redis Cluster users
3.0-rc4 2015/2/13   High for Redis if you use LRU eviction
3.0-rc3 2015/1/30   High for Redis Cluster users
3.0-rc2 2015/1/13   LOW
3.0-rc1 2014/9/19
```

### redis-3.2.x

redis-3.2 主要发布GEO支持和lua用法更新（lua debugger、effective replication、selective replication）。

其他更新包括slave logical expire；新增HSTRLEN、BITFIELD、TOUCH等命令。

#### GEO支持

从3.2开始加入GEO支持，对于地理位置相关的应用支持更加友好。

```
GEOADD key longitude latitude member [longitude latitude member ...]
GEODIST key member1 member2 [unit]
GEOHASH key member [member ...]
GEOPOS key member [member ...]
GEORADIUS key longitude latitude radius m|km|ft|mi [WITHCOORD] [WITHDIST] [WITHHASH] [COUNT count] [ASC|DESC] [STORE key] [STOREDIST key]
GEORADIUSBYMEMBER key member radius m|km|ft|mi [WITHCOORD] [WITHDIST] [WITHHASH] [COUNT count] [ASC|DESC] [STORE key] [STOREDIST key]
```

#### lua用法更新

1. Script effects replication

```
redis.replicate_commands() 
```

默认情况下，lua命令写入aof/复制时记录的是eval/evalsha命令本身。
在lua脚本中，执行任何redis写命令之前，调用redis.replicate_commands，
复制/aof中记录的就是命令本身。

redis.replicate_commands适用于计算复杂，但是产生redis.call命令较少场景。

另外可以通过以下命令，开启关闭effects replication。

```
redis.set_repl(redis.REPL_ALL); -- The default
redis.set_repl(redis.REPL_NONE); -- No replication at all
redis.set_repl(redis.REPL_AOF); -- Just AOF replication
redis.set_repl(redis.REPL_SLAVE); -- Just slaves replication
```

2. 新增lua debugger

新增了一个比较完备的debugger，提供了step, break, next, continue, 
print, trace等功能

参考材料：http://antirez.com/news/97
 

#### 主要变动

```
- Lua scripts "effect replication".
- Lua scripts selective replication.
- Geo indexing support via GEOADD, GEORADIUS and other commands.
- Lua debugger.
- SDS improvements for speed and maximum string length.
- Better consistency behavior between masters and slaves for expired keys.
- Support daemon supervision by upstart or systemd 
- New encoding for the List type: Quicklists.
- SPOP with optional count argument.
- Support for RDB AUX fields.
- Faster RDB loading 
- HSTRLEN command
- CLUSTER NODES major speedup.
- DEBUG RESTART/CRASH-AND-RECOVER
- CLIENT REPLY command implemented: ON, OFF and SKIP modes.
- BITFIELD; DEBUG HELP; GEORADIUS STORE; TOUCH; TCP keep alive is now enabled by default
```

#### 发布历史
 
 ```
 3.2.11 2017/9/21   HIGH     Potentially critical bugs fixed
 3.2.10 2017/7/28   MODERATE    
 3.2.9 2017/5/17    LOW A few rarely harmful bugs were fixed
 3.2.8 2017/2/12    CRITICAL    This release reverts back the Jemalloc upgrade
 3.2.7 2017/1/31    HIGH    This release fixes important security and correctness issues
 3.2.6 2016/12/6    MODERATE    GEORADIUS, BITFIELD and Redis Cluster minor fixes
 3.2.5 2016/10/26   LOW     
 3.2.4 2016/9/26    CRITICAL    security fix
 3.2.3 2016/8/2 MODERATE    
 3.2.2 2016/7/28    MODERATE 
 3.2.1 2016/6/17    HIGH    Critical fix to Redis Sentinel
 3.2.0 2016/5/7 HIGH    
 3.2-rc3 2016/1/28  MODERATE    fix
 3.2-rc2 2016/1/25  MODERATE    fix
 3.2-rc1 2015/12/23 
 ```

### redis-4.0.x

redis-4.0 主要发布modules子系统和PSYNC2。

其他更新包括引入lazy free机制，RDB-AOF混合存储，新增MEMORY命令以及online defragment。

详细信息参考[redis-4.0](/cdb/redis-4.0)。

#### modules子系统

redis-4.0提供了模块子系统，用于扩展redis功能。目前比较典型的模块包括：

- RedisSearch redis全文检索
- RedisGraph  A graph database with an Open Cypher-based querying language.
- rebloom  可扩展bloom filter

#### PSYNC2

PSYNC2是对PSYNC的优化，解决PSYNC存在的以下两个问题：

- slave/master重启，由于未保存重启前的runid/offset，导致全量同步
- 1主多从结构发生failover，由于新主的runid不同，导致全量同步

#### lazy free

使用后台线程异步DEL数据，API变动：

1. 增加`UNLINK key`
2. FLUSHDB/FLUSHALL增加ASYNC选项

#### 内存优化

a) 新增MEMROY命令

```
MEMORY HELP
MEMORY DOCTOR
MEMORY USAGE <key> [SAMPLES <count>] - Estimate memory usage of key
MEMORY STATS                         - Show memory usage details
MEMORY PURGE                         - Ask the allocator to release memory
MEMORY MALLOC-STATS                  - Show allocator internal stats
```

b) 新增LFU缓存剔除算法

c) 重构使得redis更加memroy efficient

#### 主要变动

```
- Redis modules system.
- Partial Replication (PSYNC) version 2.
- Cache eviction improvements. LFU算法，eviction性能、准确度提升
- Lazy freeing of keys.
- Mixed RDB-AOF format.
- A new MEMORY command. 定位内存使用问题、更详尽的内存使用报告。
- Redis Cluster support for NAT / Docker.
- Redis uses now less memory in order to store the same amount of data.
- Redis is now able to defragment the used memory and reclaim space incrementally while while running.
- 新增SWAPDB命令；新增RPUSHX and LPUSHX数量参数、INFO报告copy-on-write内存使用量、Redis部分核心重构
```

#### 发布历史

```
4.0.9 2018/3/26 CRITICAL fix fsync alaways
4.0.8 2018/2/3 CRITICAL only for cluster user
4.0.7 2018/1/24 MODERATE 32bit overflow
4.0.6 2017/12/5 CRITICAL 
4.0.5 2017/12/1 CRITICAL 
4.0.4 2017/12/1 CRITICAL
4.0.3 2017/11/30    CRITICAL PSYNC2 bugs
4.0.2 2017/9/21 CRITICAL    PSYNC2 bugs
4.0.1 2017/7/24 HIGH    PSYNC2 bugs
4.0.1 2017/7/14 MODERATE    
4.0.0 2017/7/14 CRITICAL    PSYNC2 bugs; Modules thread safe contexts ; SLOWLOG now logs the offending client name and address；GEO 
4.0-rc3 2017/4/22   HIGH    PSYNC2 bugs; Finally the infamous leakage of keys with an expire fixed; online Memory de-fragmentation; An in-depth investigation of the ziplist
4.0-rc2 2016/12/6   LOW 
4.0-rc1 2016/12/3 
```

### redis-5.0.x

redis-5.0.x主要发布新增的数据类型stream。

#### stream

Redis Stream参考kafka设计理念，

#### 主要变动

```
- 新增stream类型
- 新增redis moudles api: timers and clusters
- RDB保存RFU和LRU信息
- 集群管理功能从redis-trib转移到redis-cli中(redis-cli --cluster help)
- 新增命令ZPOPMIN/MAX以及阻塞变种
- 主动碎片整理v2
- subcommand help
- 短连接优化
- jemalloc升级到5.1
- bugfix以及其他opt
```

#### 发布历史


```
5.0-rc2 2018/6/13 CRITICAL LUA security issues; SCAN bug; PSYNC2 bug; AOF Compatibility issue; Sentinel bug; Stream bugs
5.0-rc1 2018/5/29 
```

## redis版本生命周期

通常redis版本会经过4-6个月的rc阶段，GA版本的生命周期大约两年。

```
2.8.x 2013/7/18 --(RC:4个月)--> 2013/11/22 --(GA:23个月)--> 2015/12/18
3.0.x 2014/9/19 --(RC:6个月)--> 2015/4/1 --(GA:20个月)--> 2016/1/25
3.2.x 2015/12/23 --(RC:5个月)--> 2016/5/7 --(GA:16个月)--> 2017/9/21
4.0.x 2016/12/3 --(RC:7个月)--> 2017/7/14 --(GA:8个月)--> 2018/3/26
```

## 总结

从功能上考虑，redis-2.8到redis-4.0积累了比较多的性能优化和功能更新，比如
GEO功能对于扩展应用场景、PSYNC2功能对于降低failover时全量复制概率相比redis-2.8
具有比较明显的优势。

从稳定性上考虑，通常redis GA版本发布12个月之后，出现critical bug的概率较小。

综上，建议采用redis-4.0作为redis-2.0的基线版本。

## 问题

1. 同步复制

同步复制方案是否变更到WAIT方案


## 评审问题

# Redis Stream

流数据类型。

支持三种读取方式：

- 时序数据库：按时间范围读取。
- 消息读取: 读取stream的语义类似于`tail -f`，支持多个消费者读取消息。
- 分组读取: 多客户端消费


## 命令

```
XADD key ID field string [field string ...]
summary: Appends a new entry to a stream

XLEN key
summary: Return the number of entires in a stream

XRANGE key start end [COUNT count]
summary: Return a range of elements in a stream, with IDs matching the specified IDs interval

XREVRANGE key end start [COUNT count]
summary: Return a range of elements in a stream, with IDs matching the specified IDs interval, in reverse order (from greater to smaller IDs) compared to XRANGE

XREAD [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] ID [ID ...]
summary: Return never seen elements in multiple streams, with IDs greater than the ones reported by the caller for each stream. Can block.

XREADGROUP GROUP group consumer [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] ID [ID ...]
summary: Return new entries from a stream using a consumer group, or access the history of the pending entries for a given consumer. Can block.

XPENDING key group [start end count] [consumer]
summary: Return information and entries from a stream conusmer group pending entries list, that are messages fetched but never acknowledged.

```

## 设计

### ID

Stream的数据元素标志，必须满足单调递增特性。

默认<milliseconds>-<seqnumber>，如果时间回调或者同一ms内，
milliseconds保持不变, seqnumber 64bit，所以对于日志产生
的速率无限制。

最小的id为0-1。


### 添加删除(XADD,XDEL)

```
XADD mystream * f v  # 如果是*，表示使用默认自动生成的id
XDEL <key> <ID-i>
```

不同于其他数据类型，redis允许消息数量为0的Stream存在。这是因为redis不想丢失关联
的cg状态信息。


### 时序数据库(XRANGE)

```
XRANGE mystream - + count 2 # -,+分别表示最小和最大
```

### 消息读取(XREAD)

```
xread count 5 STREAMS mystream 0
xread count 5 block 0 STREAMS mystream otherstream 0 $
```

订阅stream中的消息，当stream中收到新的信息时，订阅者将收到通知。pubsub/blocklist
已经有类似的概念，不同的是：

- stream可以有多个消费者（默认每个new entry都会被广播到所有消费者）
- pub/sub消息不保存，blocklist消费之后弹出，stream消息持久保存（除非被显示删除）

### 分组读取(XREADGROUP)

XREAD可以实现Stream和client多对一的消费关系，XREADGROUP则实现多对多消费关系。

consumer gruop(cg)有以下保证：

- 每条消息都被传递到单一个consumer(cs)
- cs是有固定身份的：在同一个cg中，cs必须带有唯一的名称
- cg保存了第一个未被消费的id
- 消息必须等到确认才能被真正消费掉（从cg的消息中移除）
- cg保存了所有pending的消息（即已经deliver但是没有ack的消息）

所以一个cg可以理解为类似以下的一个状态：


```
+---------------------------------------+
| cg_name: mygroup                      |
| cg_stream: somekey                    |
| last_delivered_id: 123434233424-94    |
|                                       |
| consumers:                            |
|   consumer1 with pending messages:    |
|      122323423423-4                   |
|      122323423423-8                   |
|   consumer1 with pending messages:    |
|      122323423433-4                   |
|      122323423433-8                   |
+---------------------------------------+
```


```
XGROUP CREATE mystream mygroup $
XREADGROUP GROUP mygroup alice COUNT 1 STREAMS mystream >
```

XREADGROUP的id分两种:

- '>' 表示返回messages never delivered to other consumers so far
- 其他数字表示history of pending messages（已经xack的消息无法访问）

需要注意的是：

- consumer第一次提到时自动创建，无需显式创建
- xreadgroup也可以从多个streams中获取消息：在每个stream中创建同名的group
- xreadgroup是一个写命令，只能在master中调用


XPENGDING & XCLAIM

由于有些svc出现永久性宕机并且无法恢复，为了接管pending的消息，可以使用xclaim
来重新获取消息的处理权。


```
XPENDING mystream mygroup # 输出pending概要信息
XPENDING mystream mygroup - + 10 # 输出mygroup 10条pending详细信息
#将<ID-1>..<ID-N>重新分配给<consumer>，并且最短idle时间为<min-idle-time>
XCLAIM <key> <group> <consumer> <min-idle-time> <ID-1> <ID-2> ... <ID-N>
```


### 信息展示(XINFO)


```
> XINFO HELP
1) XINFO <subcommand> arg arg ... arg. Subcommands are:
2) CONSUMERS <key> <groupname>  -- Show consumer groups of group <groupname>.
3) GROUPS <key>                 -- Show the stream consumer groups.
4) STREAM <key>                 -- Show information about the stream.
5) HELP                         -- Print this help.
```

### 与kafka分区的区别

kafka分区的概念与cg类似，但是streams的分区为logical分区，分区的条件是哪个客户端
当前处于ready状态。比如C3 down，那么stream将继续为C1，C2发送消息，类似于当前只有
两个分区。所以如果想要把同一个Stream分区到多个redis客户端，则需要使用cluster或者
客户端分片方法。


Stream可以使用XADD的MAXLEN选项控制进入到Stream的消息数量。

```
XTRIM mystream MAXLEN 10
```

### 复制与持久化 

与其他数据类型一样，Stream将被复制、持久化到AOF/RDB中，除此之外cg的状态也将被复制
持久化。


# RedisLabs

## RedisEnterprise

- 优化持久化层
- 基于CRDT的异地多活
- 支持多项复制和容灾选项
- global avalibity
- 智能解决双写冲突
- 支持SSD+RAM (sub-milliseconds latency, 减少开支)
- 集成检索模块达到5X检索性能
- 优化多项redis内置功能
- 支持cloud，standalone部署
- 自动扩缩容

### Active-Active Geo Distribution

对于需要全球部署的应用，主主模式提供了非常棒的可用性。并且内置的冲突解决机制
简化了获取本地低延迟和分布式高性能的开发。

Redis CRDT架构采用异地双向复制。Redis CRDT根据应用使用的数据类型和命令智能解决
冲突。

CRDT架构相比LWW(laster-write-wins)架构有很大的优势，quorum-based复制，同步主主
复制以及其他方式。通过使用CRDT，Redis Enterprise提供了：

- 使用consensus-free协议,本地读写具有很小的延迟
- 强最终一致性，提供收敛的一致性
- 内置冲突检测
- 能方便地实现分布式session管理，分布式计数器，多用户计量
- 更安全的跨地区failover


[active-active](https://redislabs.com/landing/active-active/)
[active-active-white-paper](https://redislabs.com/docs/active-active-whitepaper/)
[WP-RedisLabs-Redis-Conflict-free-Replicated-Data-Types](http://lp.redislabs.com/rs/915-NFD-128/images/WP-RedisLabs-Redis-Conflict-free-Replicated-Data-Types.pdf)
[Active-Active Geo Distribution Based on CRDTs](http://lp.redislabs.com/rs/915-NFD-128/images/DS-RedisLabs-Active-Active-Geo-Distribution-Based-on-CRDTs.pdf#_ga=2.104240642.381046220.1529399389-818448377.1524021044)

### 80% Lower Cost with Redis On Flash

对于实时分析，时序数据分析，检索，机器学习等场景使用到的内存量将非常大。使用
Flash作为冷数据的存储介质，支持大数据量和sub-millisconds延迟。

[building-large-databases-redis-enterprise-flash]()
[redis-on-flash](https://redislabs.com/redis-enterprise-documentation/concepts-architecture/memory-architecture/redis-flash/)


## 总结

 基本上商业版的思路是2B，具体还是异地复制和冷热分离。



