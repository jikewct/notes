# Redis

## RDB

### aux field


### 参考材料

https://github.com/sripathikrishnan/redis-rdb-tools/wiki/Redis-RDB-Dump-File-Format

## 协议

redis支持两种协议RESP2和inline，其中inline是支持telnet的协议，RESP2是
常规的客户端协议。

redis请求只能支持非嵌套的Multibulk，但是回复和客户端(hiredis)能支持
嵌套的Multibulk。

### RESP2


```
*1\r\n$4\r\nping\r\n
*3\r\n$3\r\nset\r\n$3foo\r\n$3bar\r\n
*2\r\n$3\r\nget\r\n$3foo\r\n


For Simple Strings the first byte of the reply is "+"
For Errors the first byte of the reply is "-"
For Integers the first byte of the reply is ":"
For Bulk Strings the first byte of the reply is "$"
For Arrays the first byte of the reply is "*"
```

### RESP3 

redis6可能唯一支持的就是resp3协议.

RESP2的最大问题就是命令的返回不是自描述的，比如hgetall返回的是个map，但是
RESP2只能描述结果为array。

作者的初心是redis6打破兼容性，原因是：
- redis5承诺2年的支持
- redis6计划在2020年发布，但是redis6大约1个月之后就会切换到resp3，给足时间缓冲
- 增加无谓的工作量
- 给大家一个整理行装，重新出发的理由
- 客户端可以同时选择同时兼容RESP2和RESP3

但是作者在开始纠结了。

## 事件循环

### readQueryFromClient

- 单次read的大小不超过16k
- 对于超过32k的bulk string, 尽量让querybuf只包含这个sds，以避免process时创建robj拷贝过大的buf

### processInputBuffer

- redis支持INLINE和MULTIBULK两种协议的命令
- block的客户端，query将被及时read，但是不会被及时process
- 解析过程中发现protocol error，client标记为`CLOSE_ASAP`
- 没有完整接收的request，不会执行processCommand

### processCommand

- 常规检查quit, command table, auth, moved, maxmemory, stop write on bgsave err, repl min slaves to write, readonly slave, pub/sub, slave server stale data, loading, lua timedout, transaction
- freeMemoryIfNeeded控制内存在maxmemory限制下，如果没控制住则返回ERR（客户端会的oom错误）
- 最终call执行命令

### call

- feed monitor, proc, propagate, also propagate
- 最终在propagate中将命令传播到aof，slaves

call在不同的场景下，使用的flags不同:

- 在server场景：CMD_CALL_FULL
- 在multi/exec场景：CMD_CALL_FULL
- 在lua场景：CMD_CALL_SLOWLOG|CMD_CALL_STATS|（如果开启replicate_commands）CMD_CALL_PROPAGATE_REPL|CMD_CALL_PROPAGATE_AOF
- 在module场景: CMD_CALL_SLOWLOG|CMD_CALL_STATS|（如果开启replicate）CMD_CALL_PROPAGATE_REPL|CMD_CALL_PROPAGATE_AOF

### propagate

propagate涉及模块lua，aof，replication，dirty等，比较复杂。


```
# 控制propagate是否开启，开启范围。比如redis.replicate_commands, redis.set_repl; module的'!'
CMD_CALL_PROPAGATE
CMD_CALL_PROPAGATE_REPL
CMD_CALL_PROPAGATE_AOF

# lua.replicate_commands时，不能propagate eval/evalsha命令，因此需要禁止propagate
# spop替换为SREM进行propagate
CLIENT_PREVENT_PROP
CLIENT_PREVENT_AOF_PROP
CLIENT_PREVENT_REPL_PROP

# script load(script cache被flush之后，重新propagate EVAL）
CLIENT_FORCE_REPL
CLIENT_FORCE_AOF

```

also propagate

call执行的时候，以下场景会引发also propagate：
- `spop [count]`命令将被替换成SREM（需要also propagate）
- lua replicate commands时，EXEC是需要also propagate的

### `AddReply*`

`addReply*`分散在数据结构中，随着命令执行reply被准备好。

#### prepareClientToWrite

决定是否需要拷贝reply到obuf，准备安装WRITE事件。

以下不添加obuf；

- lua应答不添加obuf
- `CLIENT REPLY OFF` or `CLIENT REPLY SKIP`不添加obuf
- master-link上除了`replconf ack <offset>`不添加obuf
- aof client不添加obuf

安装WRITE事件：

只有在当前没有Pending reply，并且repl state为ONLINE时才安装WRITE事件。

客户端在before sleep尝试将reply发送出去(不超过64K)，只有evloop写不完所有reply才
会安装write handler。


#### 添加到obuf

NOTE: redis-4.0之前obuf.reply为`[obj]`，4.0之后为`[sds]`。


```
c->buf          # obuf.buf, 静态reply，16k
c->bufpos       # obuf.buf read指针
c->reply        # [sds]，每个sds的大小接近16k
c->reply_bytes  # reply总大小
c->sentlen      # obuf.buf 当前正在发送的sds的指针（包括reply和buf）

addReply -- string
addReplySds -- sds
addReplyString -- buf
addReplyErrorLength -- buf
addReplyError -- cstring
...
```

### handleClientsWithPendingWrites

在epoll之前，尝试将reply尽量写完（说不定可以减少write event的安装次数）

#### writeToClient

- 按照obuf.buf --> obuf.reply的顺序发送，每个loop单个客户端最多发送64k
- 当obuf从有到无转变，则uninstall WRITE事件，关闭CLOSE_AFTER_REPLY客户端

只有在beforesleep含有没写完的客户端才需要安装WRITE事件。

## 日志

- logrotate issue为什么说redis的日志是可以随时删除的？

### 问题

- 通过对redis解析的分析，我们可以通过制造不完整的协议对redis进行DDOS攻击: `*3\r\n$3\r\nset\r\n$4\r\nddos\r\n$2147483647\r\n`
> 实际上并不可以，因为sdsMakeRoomFor最大premalloc 1MB

## Expire

- slave不会因为超时修改keyspace，master expire时通过广播DEL命令保证超时
- type, ttl命令不会更新lru

### `lookupKey*`

```
lookupKey //从expire表中查找key，不考虑超时；
lookupKeyReadWithFlags //为读操作查找key，副作用：超时;更新hits/misses;更新lru
lookupKeyWrite //expire + lookup
lookupKeyRead //expire + logical expire
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

## 数据结构

### object

可以理解为高级语言的对象，通过引用计数管理内存。

- 注意如果希望保持某一个obj，那么需要将其引用计数保持在0以上

### encodings

#### sds

- EMBSTR 为了减少sds头占用的内存，对于44B之内的String新增EMBSTR编码

#### skiplist

可以二分搜索的链表: level随机选择

#### ziplist

- memory efficient doubly linked list
- 2B overhead, 但是修改ziplist引发realloc、copy、CPU cache miss
- ziplist的entry可以支持encoding为int和raw

#### linklist

- 40B overhead, 对于小对象效率低

#### quicklist

- linked list of ziplists
- 内存效率高

[Quicklist Final](https://matt.sh/redis-quicklist-visions)

#### intset

```
typedef struct intset {
    uint32_t encoding;
    uint32_t length;
    int8_t contents[];
} intset;
```

- intset的overhead为8B
- 包括16,32,64bit 3种encoding，整个intset统一
- encoding, length按照le字节序存储
- intset按照升序排列（tricy：造成升级的value总是在head或者tail）
- `set-max-intset-entries`控制intset的element数量，默认512

#### dict(aka hashtable)

```
typedef struct dictType {
    uint64_t (*hashFunction)(const void *key);
    void *(*keyDup)(void *privdata, const void *key);
    void *(*valDup)(void *privdata, const void *obj);
    int (*keyCompare)(void *privdata, const void *key1, const void *key2);
    void (*keyDestructor)(void *privdata, void *key);
    void (*valDestructor)(void *privdata, void *obj);
} dictType;

typedef struct dictEntry {
    void *key;
    union {
        void *val;
        uint64_t u64;
        int64_t s64;
        double d;
    } v;
    struct dictEntry *next;
} dictEntry;

typedef struct dictht {
    dictEntry **table;
    unsigned long size;
    unsigned long sizemask;
    unsigned long used;
} dictht;

typedef struct dict {
    dictType *type;
    void *privdata;
    dictht ht[2];
    long rehashidx; /* rehashing not in progress if rehashidx == -1 */
    unsigned long iterators; /* number of iterators currently running */
} dict;
```

- hashtable overhead 为`96B+nelementx8`
- dictAdd添加的key在ht中必须不存在，dictReplace是如果存在则replace
- dictEntry接口：Dup(如果指定则执行拷贝，目前没有dict采用自动dup), Compare, Destructor(除expiredb外，都自动keydtor；而只有db、lua_scripts、hash、keylist(blocked_keys,watched_keys,pubsub_channels)是自动valdtor)
- hashtable对每一种哈希都有不同的配置

dictAdd和dictReplace为什么要分开实现：


### types

#### string

- set命令的特殊之处：如果key有之，那么不管什么类型，将直接覆盖

#### hash

- 编码可能为ziplist或者hashtable
- ziplist和hashtable的转换标准：value(encoding前)超过hash-max-ziplist-value(64)或者entry数量超过hash-max-ziplist-entries(512)
- ziplist存储的是raw string(decoded)

#### set

- 在什么时候进行object encoding？ 
- 是么时候开始set开始使用plain sds？为什么？
- set.hash结构为{robj(nulldup,autodtor):robj(nulldup,nulldtor)}，其中val使用nulldtor的原因是因为set只有key没有val。

#### zset

- 编码可能为ziplist或者skiplist;
- zset.ziplist按照score排序
- zset.skiplist综合使用了skiplist和hashtable存储
- zset.skiplist使用skiplist索引score，使用hashtable索引member
- 当zset成员长度小于64，元素数量小于128时可以使用ziplist编码
- zunionstore zinterstore可以在zset和*set*之间做！
- rangebylex只有在score相同的情况下才有意义，否则结果为unspecified！
- rangebylex的逻辑是score相同lex不同，但是我们需要一种方法按照lex范围查询
- zset.hashtable {robj:double}, zset.skiplist数据也是robj（hashtable查询时对不同的encoding先转换成RAW）
- redis的`-inf +inf通过shared.` `- +`通过固定的shared.minstring shared.maxstring表示

##### 关于range

range都是inclusive，zero-based index，并且能用负数表示倒数。假如zset有n个element
那么range的可用范围是`[-n, n)`。

#### list

三种encoding。

#### hyperloglog

用非常少的内存统计了scard，redis使用了12kB并且错误率只有0.81%。

### 相关issues

[关于lru，lfu value error](https://github.com/antirez/redis/pull/5011)

## lazy free

redis-4.0引入的feature，思路为使用后台线程完成异步删除。

比较有意思的是lazy free的引入，需要redis修改share everything的设计理念，同时由于
WRITE写small object效率低(writev效果也不好），所以WRITE已经在拷贝small object，
所以这个说明share small object的机制有问题。

4.0之前聚合类型的value为robj，如果不share也没必要用robj进行引用计数，因此聚合类型
表示为hashtable of sds（而不是hashtable of robj），但是带来的影响是无法复用parse
阶段创建的robj，而是需要duplicate sds，但由于redis性能由cache miss主导，因此可能
redis的性能不会因此下降。

总结下，重构做出的修改为：

- client output buf(cob)从robj修改为sds，value总是被拷贝到cob
- 所有数据结构使用sds替换robj

虽然如此，在重度sharing的replication、command dispatch等代码中依然使用robj。

结果显示在数据结构抛弃robj后，redis更加内存高效；经测试，redis更加快速。

最后lazy free特性增加了UNLINK命令，FLUSHDB/FLUSHALL增加了ASYNC选项。

由于聚合类型现在fully unshared，cob也不含有shared obj，redis可以做到：

- 可以实现多线程IO：不同的客户端可以对应不同的线程
- 可以在后台线程执行聚合类型的特定慢操作

另外可以考虑采用share-nothing架构来重构redis以获取比redis更好的性能。

### SADD SUNIONSTORE (4.0 vs 3.2)



### issues

[Lazy Redis is better Redis](http://antirez.com/news/93)
[Lazy free of keys and databases](https://github.com/antirez/redis/issues/1748)

## lua

lua特性用于实现redis事务(原子性)。

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

### 数据结构

```

server.lua
server.lua_client
server.repl_scriptcache_fifo 
server.lua_random_dirty = 0;
server.lua_write_dirty = 0;
server.lua_replicate_commands = server.lua_always_replicate_commands;
server.lua_multi_emitted = 0;
server.lua_repl = PROPAGATE_AOF|PROPAGATE_REPL;
```

### 特性实现

初始化:

```
lua_open
luaLoadLib (base,table,string,math,debug,cjson,struct,cmsgpack,bit)
luaRemoveUnsupportedFunctions //移除loadfile

//加入函数
lua_newtable
lua_pushstring
```

script load

```
//拼接f_<sha1hex>函数
luaL_loadbuffer(lua,funcdef,sdslen(funcdef),"@user_script");
lua_pcall(lua,0,0,0)

```

eval

```
/* Push the pcall error handler function on the stack. */
lua_getglobal(lua, "__redis__err__handler");//

/* Try to lookup the Lua function */
lua_getglobal(lua, funcname);
if (lua_isnil(lua,-1)) {
    lua_pop(lua,1); /* remove the nil from the stack */
    /* Function not defined... let's define it if we have the
     * body of the function. If this is an EVALSHA call we can just
     * return an error. */
    if (evalsha) {
        lua_pop(lua,1); /* remove the error handler from the stack. */
        addReply(c, shared.noscripterr);
        return;
    }
    if (luaCreateFunction(c,lua,funcname,c->argv[1]) == REDIS_ERR) {
        lua_pop(lua,1); /* remove the error handler from the stack. */
        /* The error is sent to the client by luaCreateFunction()
         * itself when it returns REDIS_ERR. */
        return;
    }
    /* Now the following is guaranteed to return non nil */
    lua_getglobal(lua, funcname);
    redisAssert(!lua_isnil(lua,-1));
}

lua_sethook(lua,luaMaskCountHook,LUA_MASKCOUNT,100000);//设置超时
err = lua_pcall(lua,0,1,-2);//执行命令

```




### replication

- eval将被完整地复制到slave中执行
- evalsha在master确认slave确认已经含有script的情况下才会执行evasha，否则将会转换成eval执行

redis-3.2引入了script effect replication和selective replication特性，用于精细
控制lua的复制方式。

```
redis.replicate_commands() #注意必须在执行写命令之前调用，否则fallback到whole script replication

# 通过函数主动控制复制范围
redis.set_repl(redis.REPL_ALL); -- The default
redis.set_repl(redis.REPL_NONE); -- No replication at all
redis.set_repl(redis.REPL_AOF); -- Just AOF replication
redis.set_repl(redis.REPL_SLAVE); -- Just slaves replication

```

### lua与aof

- eval将被原样记录到AOF中
- evalsha第一次（或者rewrite之后第一次）转换成eval执行，后续直接记录evalsha
- rewriteaof之后，aof中不再存有scriptload，evalsha等命令

### 超时

- 超时后master通过DEL命令删除slave过期key、slave从来不主动删除过期key，从而保证数据一致性
- 3.2之后slave增加了logic clock功能、除了等待master的DEL命令，slave本身也对读取命令计算超时
- lua脚本的时间静止 server.lua_start_time
- aof-binlog中删除区分DEL_BY_CLIENT, DEL_BY_EXPIRE, DEL_BY_EVICT，因此如果应用有需求不同步EXPIRE信息，这个是可以做到的

参考材料:

- http://arganzheng.life/key-expired-in-redis-slave.html
- https://github.com/antirez/redis/issues/1768
- https://github.com/antirez/redis/issues/187

## Module

### 使用


```
module load argv ... 
module unload
module list
```

### 设计思路

- static modules    {name:RedisModule}
- server.moduleapi  {funcname:funcptr}
- 每个module实现onload函数，module load时外调RedisModule_OnLoad(argv), 初始化RedisModule，添加到server.modules
- onload: svr通过ctx传入RM_GetApi指针，调用RedisModule_Ini內暴，最后被注册到server.modules
- RedisModule_Init内暴：拷贝`RM_*`函数指针到so的`RedisModule_*`指针，设置module属性
- RM_CreateCommand 注册command到server.commands


### API

module API 分为高级和低级API

#### 高级API

包括Call和一组访问reply的函数。

```
RedisModule_Call(ctx, "INCR", "sc", argv[1], "10");
ctx 
"INCR" -- 第一个参数必须是cstring command name
"sc" -- cstring format specifier
argv[1].. -- args

format specifier
--- 
c -- Null terminated C string pointer.
b -- C buffer, two arguments needed: C string pointer and size_t length.
s -- RedisModuleString as received in argv or by other Redis module APIs returning a RedisModuleString object.
l -- Long long integer.
v -- Array of RedisModuleString objects.
! -- This modifier just tells the function to replicate the command to slaves and AOF. It is ignored from the point of view of arguments parsing.
```

返回值为RedisModuleCallReply或者NULL（错误时），可以通过`RedisModule_CallReply*`
函数访问。

```
RedisModule_CallReplyType 获取返回结果类型REDISMODULE_REPLY_STRING, REDISMODULE_REPLY_ERROR, ...
RedisModule_CallReplyLength 如果string或者error，length为字符串长度；如果是array，length为元素个数
RedisModule_CallReplyInteger 获取integer类型的值
RedisModule_CallReplyArrayElement 获取array类型的子元素
RedisModule_CallReplyStringPtr 获取string类型的返回值的指针和长度，但是不能修改ptr指向的值
RedisModule_CreateStringFromCallReply 根据CallReply(string,error,integer)创建RedisModuleString
```

`RedisModule_FreeCallReply`释放reply，array类型的回复只需要释放顶层reply。

`RedisModule_ReplyWith*`回复客户端。

#### 低级API

通过`RedisModule_*Key`增删读key，`RedisModule_*Expire`操作过期。

#### 复制

RedisModule_Call的format中添加'!'表示该命令需要propagate到AOF和slaves，效果与
lua的replicate_commands效果类似，`RedisModule_ReplicateVerbatim`可以达到与lua
默认的复制类似的效果。

`RedisModule_Replicate`可以显示指定复制的命令。

在一条command中执行的复制将会通过MULTI/EXEC包装，以保证执行的原子性。

#### 自动内存管理

`RedisModule_AutoMemory`用于开启内存管理。

module中提供了一组内存申请释放API，使用这些API申请的内存可以通过INFO命令看到
统计值，并且受到maxmemory的限制。

`RedisModule_PoolAlloc`提供了类似于memory root的使用方式。

#### Native type

TODO

#### API列表

```
内存操作
---
Alloc
Calloc
Realloc
Free
Strdup

register
---
CreateCommand               注册命令
SetModuleAttribs            设置模块属性
IsModuleNameBusy            判断模块名是否被占用

check
---
WrongArity                  回复参数个数错误
KeyType                      String, List, Set...

高级API
---
Call
CallReplyProto
FreeCallReply
CallReplyInteger
CallReplyType
CallReplyLength
CallReplyArrayElement
CallReplyStringPtr

reply
---
ReplyWithLongLong           回复
ReplyWithError
ReplyWithSimpleString
ReplyWithArray
ReplySetArrayLength
ReplyWithString
ReplyWithStringBuffer
ReplyWithNull
ReplyWithCallReply
ReplyWithDouble

Key
---
OpenKey                      打开key handle
CloseKey
ValueLength             
DeleteKey
UnlinkKey
SetExpire
GetExpire

DB
---
GetSelectedDb
SelectDb

List
---
ListPush
ListPop

String
---
StringSet
StringDMA
StringTruncate


StringToLongLong
StringToDouble
CreateStringFromCallReply
CreateString
CreateStringFromLongLong
CreateStringFromString
CreateStringPrintf
FreeString
StringPtrLen
AutoMemory

replication
---
Replicate
ReplicateVerbatim

zset
---
ZsetAdd
ZsetIncrby
ZsetScore
ZsetRem
ZsetRangeStop
ZsetFirstInScoreRange
ZsetLastInScoreRange
ZsetFirstInLexRange
ZsetLastInLexRange
ZsetRangeCurrentElement
ZsetRangeNext
ZsetRangePrev
ZsetRangeEndReached

hash
---
HashSet
HashGet

IsKeysPositionRequest
KeyAtPos
GetClientId
GetContextFlags
PoolAlloc
CreateDataType
ModuleTypeSetValue
ModuleTypeGetType
ModuleTypeGetValue
SaveUnsigned
LoadUnsigned
SaveSigned
LoadSigned
SaveString
SaveStringBuffer
LoadString
LoadStringBuffer
SaveDouble
LoadDouble
SaveFloat
LoadFloat

EmitAOF
Log
LogIOError
StringAppendBuffer
RetainString
StringCompare
GetContextFromIO
BlockClient
UnblockClient
IsBlockedReplyRequest
IsBlockedTimeoutRequest
GetBlockedClientPrivateData
AbortBlock
Milliseconds

GetThreadSafeContext
FreeThreadSafeContext
ThreadSafeContextLock
ThreadSafeContextUnlock

DigestAddStringBuffer
DigestAddLongLong
DigestEndSequence

SubscribeToKeyspaceEvents
RegisterClusterMessageReceiver
SendClusterMessage
GetClusterNodeInfo
GetClusterNodesList
FreeClusterNodesList
CreateTimer
StopTimer
GetTimerInfo
GetMyClusterID
GetClusterSize
GetRandomBytes
GetRandomHexChars
BlockedClientDisconnected

SetDisconnectCallback
GetBlockedClientHandle
```

## pub/sub

- pub/sub 会被复制到slave，但是不会持久化到aof中
- 在lua脚本里头的pub/sub会不会复制到slave？

pubsub只feed到slave，不feed到aof是通过dirty不变，但是FORCE_REPL实现的。

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


## 复制

为什么redis的slave能够syncWithMaster中使用同步io函数呢？

这是因为syncWithMaster函数为read handler，没有读事件时不会进入该函数（在处理
mainloop），读取事件时syncReadline一般也就直接读取到了，在收到不含newline的回复
时，该函数将阻塞。


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

### `put_slave_online_on_ack`

为什么diskless复制需要`put_slave_online_on_ack`状态？

这是因为slave不知道什么时候rdb流截止，如果master不等待ack直接发送增量数据，
可能slave永远也发现不到rdb截止了。


### diskless

diskless优化master产生rdb的过程，该过程从生成rdb文件修改为直接将rdb数据流量写入
slaves的socket，避免对master产生磁盘压力。

由于将rdb数据流发送到slaves是子进程做的，如果部分slave发送失败，Redis父进程需要
知道具体哪些slave发送失败。Redis采用pipe传递子进程的发送报告:

1) 父进程创建pipe，整理slaves信息(fds,clientids,numfds)
2) 子进程根据slaves信息，发送rdb流并上报发送结果
3）父进程根据子进程上报的结果处置slaves

### rio



### 链式复制

- 无法向middle PSYNC如果当前middle与master的链路未连接

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

### PSYNC2

- PSYNC2依赖于rdb AUX field，那么不开启rdb下能用PSYNC2吗？ 只开启aof呢？
- PSYNC2修改cascade replication机制，是怎么考虑slave write的？

### instrospect

#### role命令

a) master

```
1) "master"
2) (integer) 1638
3) 1) 1) "127.0.0.1"
      2) "33321"
      3) "15793584"
```

#### info replication

## Lazy Free

TODO

## 内存

### MEMEORY

### Maxmemory & Oom

命令执行前或者lua执行命令前，如果发现已经达到maxmemory limit直接返回错误，不执
行该命令。

freeMemoryIfNeeded函数执行必要的检查和抢救，如果抢救不回来了那就放弃。

抢救方法：

policy分为dict选择和key选择两部分,dict选择表示选择server.db,还是server.expire。
key选择表示选择sample获取替死鬼的规则，lru表示选择idle最久的key、random表示随机
选择key、ttl表示选择马上要超时的key，noeviction表示放弃抢救。默认volatile-lru。

allkeys-lru
allkeys-random
volatile-lru
volatile-random
volatile-ttl
noeviction

NOTE：抢救过程一直持续到抢救成功或者已经牺牲了（可能循环很久）。抢救采取先污染
后治理策略(zmalloc_memory_used > server.maxmemory)。


### LFU & LRU

LFU--使用频率最低的被剔除，LRU--access最晚的被剔除。

### Active Defrag

## LRU & LFU

redis object中含有24bit的LRU clock(当前unix timestamp in seconds)。但redis没有
办法使用链表将整个database链接起来（fat pointer），因此redis采用简单采样并剔除
best candidate方法来近似LRU算法。

 3.0改进以上缺点(LRU V2) 2.8剔除没有跨db考虑，并且没有利用多次采样的信息，提高
了LRU的准确率。4.0提出了LFU算法，

redis-cli添加了一个--lru-test模式，用于测试lru的准确率。

LFU算法的基本思路即使log counter with decay。

## security 

redis不建议在一个开放的网络环境中使用，一些比较危险的命令可以通过重命名隐藏。

### protect mode

redis-3.2之后，如果redis绑定了所有的网卡并且没有密码保护，那么redis将进入protect
模式。在该模式下，redis只对来自loopback网卡的请求正常回复，而来自互联网的请求将
被拒绝。

### ACL

redis-6版本新增ACL特性。

```
#   user <username> ... acl rules ...
```

用法：

```
"LOAD                              -- Reload users from the ACL file.",
"LIST                              -- Show user details in config file format.",
"USERS                             -- List all the registered usernames.",
"SETUSER <username> [attribs ...]  -- Create or modify a user.",
"GETUSER <username>                -- Get the user details.",
"DELUSER <username>                -- Delete a user.",
"CAT                               -- List available categories.",
"CAT <category>                    -- List commands inside category.",
"WHOAMI                            -- Return the current connection username.",
```


## 错误处理

### 磁盘错误

aofflush错误；

```
server.aof_current_size
server.aof_last_write_status
server.aof_last_write_errno
```

- EVERYSEC,后台有pending flush任务时，**postpone write**
- short-write表示ENOSPC，如果ALWAYS则直接退出，如果EVERYSEC接着尝试
- 如果从short-write恢复正常，打印恢复日志
- fsync错误直接被忽略?

aofrewrite错误：

```
server.aof_lastbgrewrite_status
```
- fullresync如果无法触发aofrewrite，slave将直接退出
- rewrite的结果存储在aof_lastbgrewrite_status

rdbsave错误:

```
server.lastbgsave_status
```

如果aofflush或者rdbsave错误并且role为master，那么写命令将失败`-MISCONF`

## reply


```
int bufpos
char buf[REDIS_REPLY_CHUNK_BYTES]

list *reply //string[]，string长度接近REDIS_REPLY_CHUNK_BYTES
unsigned long reply_bytes //reply总计malloc大小
```

redis reply包括静态buf和动态reply两部分，先填满buf再写入到reply，发送时先
发送buf再发送reply。

为了将reply拼合成REDIS_REPLY_CHUNK_BYTES大小的string，添加回复到reply中存在
将小的string拷贝到大的string的过程。


```
// 添加RAW回复
void addReply(redisClient *c, robj *obj); //添加object回复 copy
void addReplySds(redisClient *c, sds s); //添加sds回复 move
void addReplyString(redisClient *c, char *s, size_t len);//添加char*回复 copy

//添加integer回复
void addReplyLongLong(redisClient *c, long long ll);

//添加status回复
void addReplyErrorLength(redisClient *c, char *s, size_t len); //添加char* err copy
void addReplyError(redisClient *c, char *err);
void addReplyErrorFormat(redisClient *c, const char *fmt, ...);
void addReplyStatusLength(redisClient *c, char *s, size_t len);
void addReplyStatus(redisClient *c, char *status);
void addReplyStatusFormat(redisClient *c, const char *fmt, ...);

//添加MultiBulk回复（multibulk只比多个bulk多一个header）
void *addDeferredMultiBulkLength(redisClient *c); //添加延迟mbheader
void setDeferredMultiBulkLength(redisClient *c, void *node, long length); //mbheadr会和后一个node粘合在一起（所以reply中的string可能超过64k)
void addReplyMultiBulkLen(redisClient *c, long length); //添加即时mbheader

//添加Bulk回复
void addReplyDouble(redisClient *c, double d);
void addReplyBulk(redisClient *c, robj *obj);
void addReplyBulkCBuffer(redisClient *c, void *p, size_t len);
void addReplyBulkCString(redisClient *c, char *s);
void addReplyBulkLongLong(redisClient *c, long long ll);

```

## 超时

```
server.repl_transfer_lastio : slave CONNECTED之前，只要收到任何来自master的消息就更新
client.lastinteraction      : 客户端Write或者Read数据就更新（除master客户端，master客户端只有READ才算有更新）
client.repl_ack_time        : slave向master发送newline心跳(fullresync load rdb)、PSYNC、REPLCONF ack/acksn、putSlaveOnline(disk or diskless)
```

### 主断从链

- ONLINE的slave如果repl_ack_time超过repl_timeout，master关闭slave连接

### 从断主链

- 建立主从关系期间，如果server.repl_transfer_lastio超过repl_timeout则重新开始建立主从关系
- 已经建立主从关系，如果master.lastinteraction超过repl_timeout断开连接

### 普通客户端超时

- 如果客户端空闲时间超过timeout，客户端将被断开

### 参考

[Redis Security](https://redis.io/topics/security)
[A few things about Redis security](http://antirez.com/news/96)
[Redis Lua scripting: several security vulnerabilities fixed](http://antirez.com/news/119)
[Clarifications on the Incapsula Redis security report](http://antirez.com/news/118)

## keyspace notify

- 通过pub/sub实现通知
- 包括key-space、key-event两个维度的通知，分别针对key和cmd
- 通过`config set notify-keyspace-events AKE`设置

events列表:

```
DEL
RENAME
EXPIRE
...
EXPIRED
EVICTED
```

关于redis中的keyspace notify的缺陷：
https://github.com/antirez/redis/pull/5585

## blocking operation


```
blpop, brpop, brpoplpush, bzpopmin, bzpopmax
```

```
server {
    db[]: db {
        blocking_keys: {key => [client]}
    }

    blocked_clients
    blocked_clients_by_type
}

client {
    flags
    btype
    ...
    bpop {
        timeout
        target
        keys {key => keydata}
    }
}
```

- 对于block在多个key的client： `client->keys`和`server->blocking_keys`都有多个entry。
- 客户端BLOCKED之后，只会读取query，但是不会处理querybuf
- 客户端UNBLOCKED之后，在beforeSleep会处理积压的queybuf
 
handleClientsBlockedOnKeys


## multi/exec


```
server {
    db {
        watched_keys { key => [client] }
    }
}

client {
    watched_keys : [watchedKey { key, db} ]
}
```

signalModifiedKey

- 在watch了谁和谁被watch了两个维度进行了记录
- watchedKey包括db和key两个要素
- watch-set-multi-exec会导致exec失败, watch-multi-set-exec不会
- watch之后expire,evict都不影响事务提交
- watch不存在的key，别的客户端添加了这个key，那么提交失败

## maxmemory

slave设置的maxmeory没有作用，对于数据的最终解释权全部在master上！

## swapdb

swapdb命令涉及的方面很多：

- block




- trans

- script

- replication



## 单元测试

### tag系统

redis单元测试中的tag用于标记类别，每一个测试案例可以打上多个tag。

单元测试系统可以设置tag白名单和黑名单，用来选择过滤不用的测试案例集。

用法:

```
./runtest --tags {allowtag -denytag}
```

实现:

```
$::denytags #tag黑名单：黑名单优先级最高，默认空
$::allowtags #tag白名单: 白名单默认全部
$::tags #用于记录当前执行代码所属的tag

proc tags {tags code} #给code添加tag的函数

```

具体应用：

rks对于某些命令暂时不支持，可以使用该特性过跳过不支持命令的测试案例。

### 测试案例

#### 复制

replication:

- 通过repl-disless-sync观察handshake状态
- 观察block operation是否能正常复制 
- 观察role，master-link-status进行复制状态监测;flushall, set k v命令传播
- 观察在diskless yes&no的情况下，1主2从在write_load的情况下，最后的dbsize和debug digest相同

replication-2:

- 通过set/get命令观测min-slaves-to-write、min-slaves-max-lag在master，slave上的遵守情况
- createComplexdata，然后比较主从之间的复制数据是否一致。

replication-3:

- MASTER and SLAVE consistency with expire; createComplexDataset useexpire
- eval在master-slave间正确复制，并且最后通过dbsize，debugdigest，以及csvdump判断数据一致

replication-4:

- Test replication with parallel clients writing in differnet DBs，最后用dbsize,debug digest判断一致
- 测试min-slaves-to-write、min-slaves-max-lag选项
- debug digest验证长参数复制

replication-psync:

在$duration时间内，如果$reconnect, 则slave每2s断链一次，每次持续$delay时间。
最后关闭写入压力，检查主从是否数据一致(每s一次，持续10s）

## sentinel 测试

./runtest-sentinel

### 测试框架

与redis的单元测试不同，sentinel的测试没有采用client-server架构，而是采用的比较
简单的顺序模型。

### 案例

00-base: kill master --> 选择了新master --> slaves指向新master --> 旧master变成slave --> 设置qurum不可达到,kill master：不发生failover --> kill掉qurum个sentinel，kill master: 不发生failover -->  设置qurum与sentinel数量相同，killmaster: failover正常
01-conf-update: 在一个sentile down时，sentinels能够failover --> sentinel up后，能够获取新的配置
02-slaves-reconf: kill master，检查所有的slave向新的master复制（并且master-link-status是up） --> 在少了一个slave的情况下，kill master然后：检查failover和复制 --> 检查每个sentinel是否有完成failover  --> 重启slave，检查复制link
03-runtime-reconf: 空？
04-slave-selection: 空?
05-manual: 测试sentinel failover命令正常：failover发生，新master复制关系搭建，旧master复制关系搭建
06-ckquorum: 测试sentinel ckqorum命令正常检查到NOQUORUM 和 NOAUTH

对于rks的测试而言，需要修改kill instance和restart instance的方法（因为rsync进程会清理不掉）
对于rds的测试而言，应该不需要任何改变。

## db

redis支持多个db。

```
typedef struct redisDb {
    dict *dict;                 /* The keyspace for this DB */
    dict *expires;              /* Timeout of keys with a timeout set */
    dict *blocking_keys;        /* Keys with clients waiting for data (BLPOP) */
    dict *ready_keys;           /* Blocked keys that received a PUSH */
    dict *watched_keys;         /* WATCHED keys for MULTI/EXEC CAS */
    int id;
    long long avg_ttl;          /* Average TTL, just for stats */
} redisDb;

typedef struct redisClient {
    redisDb *db;
    ...
}

typedef struct redisServer {
    redisDb *db;
    int dbnum;                      /* Total number of configured DBs */
    ...
}

#define REDIS_DEFAULT_DBNUM     16

dbnum是一个不能动态修改的参数。
普通客户端默认db为0，lua脚本的db与当前客户端相同。

int selectDb(redisClient *c, int id);

```

涉及db的命令

```
select
move
```

### UPRedis冷热分离支持多个db


#### column family

cf的主要思想就是share wal,don't share sst memtable。share wal可以保证原子性，
unshare sst,memtable可以独立配置独立删除。

只要任意一个cf flush，wal都会切换下一个。但是有mem对应的wal就不能被删除，因此
在性能调优方面有一些有趣的细节和实现。

问题：

- 首先cf是需要初始化时候创建还是能动态创建，重启的时候能动态扩展么？
- cf有一些资源是共享的，那么怎么着共享，会不会影响和redis.db对应？
- 如果对应怎么实现？


```
创建cf
db->CreateColumnFamily(ColumnFamilyOptions(), "new_cf", &cf);

关闭cf
delete cf;
delete db;

删除cf
db->DropColumnFamily(handles[1]);

列出cf：
DB::ListColumnFamilies(const DBOptions& db_options, const std::string& name, std::vector<std::string>* column_families)


https://github.com/facebook/rocksdb/blob/master/examples/column_families_example.cc
```

参考:https://github.com/facebook/rocksdb/wiki/Column-Families#backward-compatibility

#### 设计思路

- cf与db一一对应
- 初始化创建? 打开？退出时关闭?
- 每个命令的提交用rksCommit提交到`client->db`
- redisDb数据结构添加cf，db的名称就是0,1,2,...dbnum
- 所有调用rocksdb_put、rocksdb_get的命令都需要修改到putcf,getcf

## debug

redis提供了debug命令。

### debug digest

计算所有db的一个hash摘要，可以用于判断数据是否一致。

- mix: digest = SHA1(digest xor SHA1(data))，需要保留顺序影响时使用
- final = mix(db,mix(key,type,node,node,"!!expire!!");

对于rks来说，我们可以直接对所有的meta和node进行没有迭代，然后直接sha1ctx。

## defragment

# redis cluster

redis作者对于cluster是否production ready的评价：

```
Hello, your question would deserve a very long reply, but this TLDR 
will be likely more useful to you: 

1) Yes it is a stable product that can be used in production with success. 
2) Sharding and failover are the best available with Redis AFAIK. 
While there are similarities with Sentinel the fact that Redis Cluster 
is centralized has advantages. 
3) Quality of client libraries around is very low. This si a major 
problem sometimes. 
4) Resharding and rebalancing are slow, so if you want to dynamically 
move things among nodes, it's not going to be very fast. It was 
improved significantly with new multi-keys MIGRATE but still there is 
work to do. 
5) Tooling is very scarse: there are not monitoring and backup/restore 
tools, so you have to invent your things. 
6) redis-trib itself, the management utility, should be more robust. 

So IMHO it's a system that has a lot of margin for improvements, but 
that is already usable in different production scenarios. However I 
would advise people using it at scale to understand how it works very 
well: one of the advantage of Redis Cluster is that a single developer 
without a huge experience in distributed systems can understand it all 
in a small amount of time. 

Cheers, 
Salvatore 
```

总体上:

- stable
- 高可用特性好
- 目前客户端质量比较差，有时候可能是个比较大的问题
- resharding & reblancing比较慢？
- 监控、备份、恢复工具缺乏

当前作者也在关注cluster-proxy类似项目。

一些比较感兴趣的点：

- cluster failover是安全且没有数据丢失的，这是如何做到的？
- resharding和rebalancing怎么做？resharding和multi-key MIGRATE?
- lua脚本/通过hashtag路由到相同slot的key/在resharding过程中怎么做到原子性？
- 热点key，大key，不均衡怎么办？

cluster方案:

优点:

- 官方维护的代码，开源社区测试，更加有保障
- 扩缩容流程更加平滑（不需要申请大量的资源）
- 监控管理大有可为（可以做热点预警，动态迁移，横向扩容）
- failover不丢数据

缺点：

- 没有upredis产品生态完善：比如说没有冷热分离和异地同步功能
- 客户端不完善 (使用cluster-proxy方案)
- 监控管理工具目前还不完善 (dbass开发监控管理/dbaas工具)

直观上感觉，目前cluster还是不要推进为好！


# Redis sentinel

## 实现细节

tilt:

正常两次timer事件大概事件间隔为100ms，如果两次定时事件间隔超过2s或者时间
回调，则sentinel进入到tilt模式。进入tilt模式后，持续30s只monitor不act。



```

sentinelState {
    current_epoch
    masters
    tilt
    tilt_start_time
    running_scripts
    scripts_queue
}

sentinelRedisInstance {
    config_epoch
    name 
    runid

    promoted_slave
}
```

ASK/LOBBY

```
SENTINEL is-master-down-by-addr <ip> <port> <epoch> <*|runid>
<down?> <*|leader runid> <leader epoch>
```

### 什么样的是一个bad slave？

- sdown/odown/disconnected/hang(info超过5s或者30s未更新)/obselete(sentinel在repl-link down超过3分钟之后，才发现sdown)


## 问题

- 每个sentinel能监控多个master，那么sentinel对A、B、C三个master记录的不同状态存放在哪里？
  当前sentinel的观点存放在master中，其他sentinel的观点存放在sentinel中


# Redis-cli

# Redis-benchmark

redis-benchmark用法可以分为默认testsuite和自定义testsuite两种模式，如果arg之后
还有参数，则使用自定义testsuite模式，否则使用默认testsuite模式。

默认testsuite使用-t <case1>,<case2>...<casen> 指定，包括：
ping, set, get, incr, lpush, lpop, sadd, spop, lrange, mset

redis-benchmark 采用并没有采用异步api驱动，


```
client := (
    context     //hiredis链接
    obuf        //output buf
    [randptr]   //pointers to __rand_int__ in command buf
    randlen     //# pointers
    randfree    //# unused pointers in randptr
    written 
    start
    letency
    pending     //# pending requests
    prefix_pending // # pending prefix commands
    prefix_len     // Size in bytes of pending prefix commands 
)


write:
randomizeClientKey
写完整个obuf
安装readHandler

read:
先read
redisGetReply解析buffer
丢弃prefix commands
统计latency
clientDone:
    判断是否任务完成
    否则resetClient(keepalive):
        删除read事件，安装write事件（但是obuf不会重新组装）


综上：redis-benchmark使用了ae进行异步执行，但是并没有使用redis的异步api。

```

latency: 

统计方法是每一个request都统计一个对应的latency，最后在进行sort，并给出report。


# Hiredis

## 协议相关

Reader: 解包
Format: 粘包

## 同步

- redisGetReply先发送，后读取，再处理
- processItem返回REDIS_ERR表示停止解析：如果buffer空，reader状态正常；如果解析出错，调`__redisReaderSetError__`设置且通过redisReaderGetReply返回值表示
- redisReply是多态类型，MULTIBULK对应ARRAY，ARRAY中的每个元素又是一个`redisReply*`
- commands采用了printf设计模式

## 异步

总体思路就是hiredis实现读写ev，借用事件库驱动各连接的ev。
一个请求对应一个cb注册到ctx的cb列表中，当读取到回复之后，按照顺序执行对应cb。

## 非阻塞

W:redisBufferWrite
R:redisBufferRead

## monitor和subscribe

## Free与Disconnect

- redisFree是针对内存/fd的操作，同步关闭链接直接redisFree；
- redisAsyncFree清理cb，清理内存，ev（不能在cb中直接__Asyncfree）
- redisAsyncDisconnect为了达到clean disconnect（后续不能发起请求，目前obuf要全部发送并且应答要全部收齐)

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

# redis-migrate-tool

## 用法

模式(默认redis_migrate):


```
[-C redis_migrate|redis_check|redis_testinsert]
```

命令：

```
PING
INFO
SHUTDOWN
```

支持从RDB、AOF、SINGLE、TWEMPROXY到RDB、AOF、SINGLE、TWEMPROXY。
 
支持通配符过滤。

存量数据会校验冗余、增量数据不校验冗余。

不支持EVAL/EVALSHA。


## redis_migrate


### 初始化

- 读线程配比20%写线程80%
- 按照unsafe和safe读，safe模式一个ip上的两个redis实例不同时读，避免同时触发bgsave
- 读写线程都是按照srnodes均分的（因为读写线程的任务都来自于srnodes）
- 读写线程通过srnode.socketpair通知对方


### 事件循环

- readThreadCron:

检测执行shutdown
执行redisSlaveReplCorn

- writeThreadCron

检测执行shutdown
如果需要，重连（连接、auth、创建事件）

- begin_replication

读取通知
转到rmtConnectRedisMaster

- rmtConnectRedisMaster

连接srnode
转到rmtSyncRedisMaster

- rmtSyncRedisMaster

复制握手
转到rmtReceiveRdb

- rmtReceiveRdb

收取rdb流
如果rdb.type为RDBFILE，则写入到node-xx文件
如果rdb.type为MEM，则数据存到srnode.rdb.data，通知相应写线程
收取完毕之后，通知写线程notice_write_thread，转为增量数据传输rmtRedisSlaveReadQueryFromMaster

- rmtRedisSlaveReadQueryFromMaster

读取propagate流，数据存入srnode.cmd_data，通知写线程notice_write_thread

- parse_prepare

删除fdpair[1]读事件，创建socket:sk_event（将持续触发写事件）, 并创建相应的写事件redis_parse_rdb

- redis_parse_rdb

以一个较小的step循环解析rdb文件:redis_parse_rdb_file。

redis_parse_rdb_file:
    解析rdb文件，每解析到一个记录都: 
        检查归属（SINGLE或者源数据为twem-random或者twem-others且源数据归属地正确）
        检查是否符合过滤规则
        调用rdb.handler:redis_key_value_send
            路由选定目标节点
            redis_generate_msg_with_key_value: 根据key类型，生成redis协议报文
            prepare_send_msg: 检查并建写立线程与trnode的连接，将报文存入trnode.send_data，并创建写事件send_data_to_target,
    验证checksum

解析完成后，删除sk_event写事件。
创建sockpairs[1]读事件parse_request
通知写线程，notice_write_thread
通知读线程从下一个srnode获取rdb文件

- parse_request

按照从srnode.rdb.data到srnode.cmd_data的优先顺序，将rdb或者cmd数据解析
prepare_send_data:
    检查命令是否支持，如果不支持则打印日志，并直接跳过
    过滤消息
    fragment、路由、prepare_send_msg

- send_data_to_target

发送trnode.send_data

- recv_data_from_target

读取target的回复，解析，如果解析失败日志记录失败（但是不会断链接）


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

#### module子系统

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

Redis Stream参考kafka设计理念。

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
5.0.1   2018/11/7 CRITICAL for Stream users
5.0.0   2018/10/17 CRITICAL 
5.0-rc6 2018/10/10 HIGH AOF bug, 不用slave名词，LOLWUT
5.0-rc4 2018/8/3 HIGH localtime, redis-cli fix, active defrag 可以在redis5中使用
5.0-rc3 2018/7/13 LOW
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
5.0.x 2018/5/29 --(RC:5个月)--> 2018/10/17 --
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

XDEL key ID [ID ...]
summary: Removes the specified entries from the stream. Returns the number of items actually deleted, that may be different from the number of IDs passed in case certain IDs do not exist.

XGROUP [CREATE key groupname id-or-$] [SETID key id-or-$] [DESTROY key groupname] [DELCONSUMER key groupname consumername]
summary: Create, destroy, and manage consumer groups.

XINFO [CONSUMERS key groupname] [GROUPS key] [STREAM key] [HELP]
summary: Get information on streams and consumer groups

XPENDING key group [start end count] [consumer]
summary: Return information and entries from a stream consumer group pending entries list, that are messages fetched but never acknowledged.

XTRIM key MAXLEN [~] count
summary: Trims the stream to (approximately if '~' is passed) a certain size

XACK key group ID [ID ...]
summary: Marks a pending message as correctly processed, effectively removing it from the pending entries list of the consumer group. Return value of the command isthe number of messages successfully acknowledged, that is, the IDs we were actually able to resolve in the PEL.
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

### 能否用stream替代kafka

redis stream怎样进行横向扩展？
> 通过客户端pre-sharding实现横向扩展


kafka目前的劣势：

- 比较重量，云闪付团队对API使用方式不熟悉，容易踩坑
- 资源要求多：需要磁盘，CPU，内存
- 分区数量不能太多（由于磁头数量少，分区太多细碎导致性能下降），同时又不能多个消费者消费同一个partition
- 高可用方面不太友好？

通常应用的配置：异步写、异步复制(ack=1)、mmap不刷盘

优势：

- TPS比较优秀
- 能够存档历史数据，可以返回去重新消费


# Redis Cluster

- 主从结构，AP系统（异步复制，数据可能丢失，last failover win一致性）
- 16k slot拆分，客户端redirect，支持manual resharding
- gossip over clusterbus

## 问题

- 怎么组建cluster集群，分配slot，开始接受请求？
- 怎么做failover，怎么保证manual failover过程中不会出现数据丢失?
- 怎么做数据重新分配，如果出现了严重的数据倾斜怎么办？
- cluster到底目前为什么没有在生产中使用？主要的障碍是什么？是否要推cluster方案？如何解决C客户端问题？
- redis-cluster-proxy方案如果可行，是否可以使用cluster代替twemproxy方案实现更加平滑的扩容？基于cluster的异地方案(支持非对等的异地?）？

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

 基本上商业版的思路是2B，落地功能点为异地复制和冷热分离。


# contrib

- evict.c:444 typo

# upredis-tests

## tcl

tcl的设计受shell影响较大，但是补全了shell中缺少的namespace
param package scope file socket等缺失特性。

package
source
set
::
proc
{}
[]
''
""
dict
args
global
upvar
argc
argv0
argv
pkg_mkindex
load
_

socket
fconfigure

end

exec


## tcl-redis

c/s模型，多进程socket通信。

### 使用方式

./runtest --help 
--valgrind         Run the test over valgrind.
--accurate         Run slow randomized tests for more iterations.
--quiet            Don't show individual tests.
--single <unit>    Just execute the specified unit (see next option).
--list-tests       List all the available test units.
--clients <num>    Number of test clients (default 16).
--timeout <sec>    Test timeout in seconds (default 10 min).
--force-failure    Force the execution of a test that always fails.
--help             Print this help screen.

--tags <-denytag|allowtag>
--client <port>
--port
--accurate 

### c/s模型

test_server_main
    accept_test_clients
        read_from_test_client

消息格式
<bytes>\n<payload>\n 

c-->s: <status> <details>
status包括：ready, testing, ok, err, exception, done
s-->c: <cmd> <data>


需要注意的是这里的c/s与redis-server，redis-client概念不同。

测试中的c完成了启动svr，连接svr，发起命令和收集结果；
测试中的s完成测试任务分发，测试结果收集，测试客户端管理。


### 小结


# twemproxy

## hash tag



# bugs

mset没有signal modified key
sinter三大件中缺少


# 业界动态

周边工具:

redis-faina
redis-port

可以用于培训的材料： https://yq.aliyun.com/articles/557508


## 阿里

### proxy

https://yq.aliyun.com/articles/241237

- client命令目前支持client list, setname, getname, kill四个sub command.
- sunion, sdiff, sinter, sunionstore, sdiffstore, sinterstore, zinterstore, zunionstore 集群规格中，这几个命令不再要求所有key必须在同一个slot中，使用和主从版没区别。
- info命令, info key user_key, info section, iinfo dbidx, riinfo
- monitor命令, imonitor, rimonitor
- scan命令, iscan

以上这些功能，阿里云已经在2017-11-12之前完成。

### redis

阿里云的混合存储使用的nvme磁盘，后台控制冷热数据，并采用双写方案。

#### 容灾

2018年2月

https://yq.aliyun.com/articles/403312

#### 混合存储

2018年4月

- 90% cachemiss情况下，可以达到70%的性能
- 存储引擎采用Fusion Engine
- NVMe磁盘存储
- bio线程增加SWAP/LOAD线程，异步处理冷热交换

所有key保存在内存中，热点value保存在内存中，其他value保存在磁盘。
SWAP线程将数据存储到rocksdb引擎。

感觉上隐藏了比较重要的两个问题：

- 大key问题
- 性能随着时间的曲线问题

#### 多线程


#### 异地多活

- AOF-BINLOG


- CRDT

https://yq.aliyun.com/articles/635628

目前看来CRDT并不能解决所有的redis数据类型的最终一致性问题，只能解决
部分数据结构，部分数据用法的最终一致性。

https://yq.aliyun.com/articles/635629

若命令集内所有命令间均具备交换律、结合律的，直接回放操作(op-based CRDT)
若命令集对应的数据类型是set，使用基于时间戳做tag的OR-Set策略
其它情况使用LWW(Last write wins)策略


## sohu

- sohutv cachecloud: https://github.com/sohutv/cachecloud
- 可以给出监控，集成的灵感


## netflix

dynomite: 设计目标是为kv数据库附加高可用和容灾能力。

目前看来应该是用户不多的。

https://github.com/Netflix/dynomite

# CRDT

参考: https://github.com/orbitdb/ipfs-log
阿里方案

## counter

Op-based counter

G-Counter

PN-Counter 两个G-counter

## Register

LWW Register: 带时间戳

## Set

Grow-Only Set (G-Set)

2P-Set： 1）删除了之后就没法添加，删除的元素占用空间

LWW-element-Set: 

Observed-Remove Set (OR-Set):



# 相关

## key-value storage

apple/foundationdb ACID，性能也不错

## redis cluster

joyieldInc/predixy A high performance and fully featured proxy for redis, support redis sentinel and redis cluster
