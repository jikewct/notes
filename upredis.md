# upredis

## upredis版本

### upredis发布

- upredis-1.2.0 没有编译12sp1，导致1.3.0,1.4.0都没有12sp1的介质



# upredis-2.0

# 协议

```
#发起psync
psync <runid> <offset> <opid> <server_id> <slave_repl_version> <current_master_runid:??> 

#psync失败后，强制sub-slaves resync //TODO 如果slave不支持呢？另外发送了之后就直接close客户端不会造成收不到么？收到了要回复么？
forcefullresync

#全量同步完成后，强制同步主从offset
syncrepoffset <repl_offset>

replconf ack <reploff>

replconf ack-opid <next_opid>

"+CONTINUE\r\n"     #PSYNC continue无需告知<runid> 因为runid变更了无法PSYNC；PSYNC2需要告知<runid>，因为runid变更了也可以continue(比如failover），并且slave需要更新runid
"+AOFCONTINUE\r\n"
"+FULLRESYNC <runid> <offset> <next_opid> <applied_info{ssid:applied_opid ... ssid:applied_opid}> <aof-psyncing-state>\r\n"

#只要是upredis-2.0的slave，就在PSYNC的回复前面加上REPL_VERSION前缀
"+REPL_VERSION <master_repl_version>  00000...000 [+FULLRESYNC...]|[+CONTINUE...]|[+AOFCONTINUE...]"
```



# replication

## 数据

server.master.flags.REDIS_AOF_PSYNCING
server.do_aof_psync_send
server.aof_psync_cur_reading_name
server.aof_psync_slave_offset{fd,}
server.repl_master_initial_applied_info
server.repl_master_initial_opid
server.repl_master_aof_psyncing_state

client.flags.REDIS_AOF_PSYNCING


几个runid：

server.runid    #自身runid，记录当前server runid
server.master_repl_offset #自身offset，记录当前server reploff

server.repl_master_runid #+FULLRESYNC解析结果
server.repl_master_initial_offset # +FULLRESYNC解析结果

server.master.replrunid # 从master拉取全量完成，进入CONNECTED状态时保存server.repl_master_runid；发起 PSYNC时也是使用的该id。
server.master.reploff # 保存了master的实时复制offset

server.cached_master # 主从之间断链，则把master链接缓存到cached_master，并将server.repl_state设置CONNECT（发起重连）；重连过程中优先使用cached_master进行PSYNC；如果PSYNC成功，则复活cached_master；否则抛弃cached_master，通知下线重新同步；

## 问题

// TODO 为什么feed slaves不需要del_type ？ 
因为复制流不需要区分del_type，这应该有错误的！


//TODO fullresync完成之后需不需要startBGSaveForFullResync()??? 首先FULLRESYNC过程中的rdb文件呢？这个过程会不会出发save？

## 碎碎念

- 进入了aof-psync状态后： c->flags |= REDIS_AOF_PSYNCING;
- master进入aof-psync时，会将添加syncreploffset <server.master_repl_offset>
- 由于redis-2.8暂时没有PSYNC2，所以目前upredis-2.0也不支持PSYNC2
- replconf getack, replconf ack 都是没有回复的单向消息！
- fullresync之后，server.next_opid = server.repl_master_initial_opid, server.master.flags |= REDIS_AOF_PSYNCING
- 目前的<current_master_runid>定死为??可能是psync2之前的方案。
- slaveof当前slave？？redis-2.8如何处理？
- REPL_VERSION的作用：master告知slave自己能否处理replconf ack-opid <next_opid>
- AOF-PSYNC只能解决backlog容量不够的问题，不能解决PSYNC2解决的问题；
- 只要复制角色发生变更，那么都会触发aofsplit(TRYDEL, FORCESPLIT)
- feedslaves居然是用的是shared.oplogheader, shared.opinfo；master给slave发送的opinfo是未解之谜！！!难道发送给slave只是一个占位符？？？？？？？
- 擦擦擦，刚刚发现apsaracache居然没有aof-binlog就玩不转了！不过策略还是先采用apsara的策略，最后优化修改。

## 测试案例

1. 测试slave全量同步时，sub-slaves的情况！
2. 因为有多个地方使用了4k的占内存，测试在比较小的占内存情况下，会不会崩溃
3. 测试PREPSYNC场景
4. 因为AOF文件可能头和尾都有opinfo命令，因此需要考虑和测试不同场景是否会有问题！

# AOF


## 数据结构

server.master.lastcmd
server.last_aof_open_status
server.aof_buf
server.aof_fsync
server.aof_rewrite_buf_blocks # 用于记录rewrite阶段的aof diff
server.aof_queue # apsara新增的用于记录aof任务的队列
server.aof_select_db

server.aof_psync_cur_reading_name

## 命令

aofflush
purgeaofto <aof_filename>

## 配置

auto-purge-aof
auto-cron-bgsave

## split

role变动，aofflush命令，aof文件大小超限，rdbSaveBackground

## purge

- aof-inc.index超过1M*80%：尽量删除aof文件；
- aof总量超过max-keeping(2*max-memory||5G)：只留5G
- purge会考虑以下因素，并且不删除正在使用的aof：
    - 被purge的aof是否在rdb.index中存在
    - server.aof_filename
    - server.aof_psync_cur_reading_name
    - opdel earlist aof file
- purge完成之后还需要更新aof-inc.index文件, server.min_valid_opid


 delAofIfNeeded可能会出现当前rdb与一个很老的aof文件对应，但是中间又生成了很多空的aof文件
 造成aof-inc.index文件超过限制：：：能不能避免产生空aof文件！！

## cron

- 每30s，deleteAofIfNeeded
- 每HZ，查看当前文件是否超过大小限制，如果超过限制，则发起aofSpilt

## write&flush

- aof的常规fsync（everysecond，always）逻辑不变
- aof bio fsync，将fsync任务发送给bio线程:aofQueueHandleAppendOnlyFlush




## 问题

// TODO when stop aof ? why? 
stopAppendOnly
做法：flush当前文件，放弃bgrewrite。
场景：config set appendonly no; fullresync开启aof新纪元
NOTE: flushAppendOnly没有返回值!! redis的数据居然这么没有保障！


startAppendOnly
做法：打开aof文件，开启bgrewriteaof
场景：config set appendonly yes；fullresync开启aof新纪元
NOTE: 写是有判断的

## 碎碎念

## 测试案例


# aof_buf_queue

新增bio sync处理appenonly的aof_buf写请求

## 数据结构

server.aof_buf_limit
server.aof_current_size
server.aof_total_size
server.aof_inc_from_last_cron_bgsave

## 配置

## 问题

## 碎碎念

- 如果force，那么不进行流控（然而force只在bio-->其他时触发）

## 测试案例


# RDB

## 数据结构

## 问题

// TODO WTF is auto sync for incr fsync ??
每32M fsync一次RDB

// TODO prepare what ?
flushAppendonly
aofSplit(0,0)

//TODO WTF info is included ??
主要搜集cronbgsave过程中使用的内存


auto-cron-bgsave:

cronBgsave触发


## 碎碎念

- 每次rdbsave都会先split一把

## 测试案例





# 问题

master，slave的offset如何保持一致，特别实在master需要向slave发送DEL(by expire)，PING，REPLCONF命令时保持一致！
- 第一个是为什么psync可以保证？
- 第二个是为什么aof-psync不可以保证？






# 测试

- 出现了aof-index含有重名aof文件
- 如果svr，slv启动在同一个文件夹？

- redis-1.2 作为slave挂在redis-2.0上出现coredump

目前已解决，Apsara也有这个问题！



- slave opid信息显示不正确！




--------------------
- 为啥createbacklog时自增1，slave能知道offset是多少，也就是说fullsync的init offset是怎么告知的？
开始的offset, +FULLRESYNC <runid> <offset>
只要没有slave，则master_repl_offset为0；创建backlog，master_repl_offset++；feedReplicationBacklog时reploffset+=len
create/resize backlog时，repl_backlog_off = master_repl_offset+1

- 为啥aof-psync需要syncreploffset?
因为没有通过+fullresync拿到offset，但是aofcontinue了；这样的话下次想psync还得不到正确结果。

- 为什么syncreploffset使用的是dosendaof完成的master_repl_offset，而不是aofcontinue时的master_repl_offset?

从aofcontinue到dosendaof完成，master_repl_offset是会增加的；但是因为aof文件同步增加，并且aofcontinue之后的命令会不会发送给slave client

- psync,aof-psync,sync的优先级？

psync > aof-psync > sync

-------------------
以下问题：

- 迁移问题
- 兼容性问题
- 为什么会有如此多的空aof文件
- monitor问题
- sub-slaves的考量
- 测试问题, tcl脚本！


-----------------
测试案例：

多个slave同时进行aofpsync

查找find_offset_by_opid出错，导致forcefullresync

模拟全渠道的案例进行测试。
怎么考虑aof，rdb的兼容性问题
复制gap怎么处理，能否使用时间戳处理99%的数据冲突

multi/lua/expire/replication/aof/scriptcache/monitor/pubsub/keyspace

bug怎么处理？

-----------------
bring it together

关于复制：

- 为什么aofpsync之后需要forceresyncoffset(而不是aofcontinue runid offset)？aofpsync怎么完成的，psync怎么完成的?
- 在master在进行psync时，subslaves是否能psync？fullresync呢？
- backlog怎么切换，backlog的产生和消失时机？offset的增加时机？

关于lua：

- 怎么优化lua的evalsha在aof中的存储命令?lua script cache在什么情况下需要flush

关于expire：

- 什么时候expire？maxmemory？


----------------
server.aof_psync_slave_offset全局唯一，说明同时只能有一个slave进行aofpsync，那么是怎么保证的呢？
通过server.do_aof_psync_send标志标记该状态
preamble? slave.repldbfd, slave.repldboff, slave.repldbsize??


----------------
什么是debug digest，所有db数据的摘要。
debug loadaof
由于server.aof_filename目前

-------------------
aof-->aof-binlog

- bgrewriteaof将当前数据全量保存为appendonly (Point-In-Time)
- aof仅用于保存PIT数据，因此aofrwbufblocks不在使用
- rdb仅用于保存PIT数据。


auto-cron-bgsave:


save directive 与 auto-cron-bgsave怎么相互影响？

如果

appendonly no时, 开始bgsave; 同时config set appendonly yes;
然后开始大量写入，触发auto-cron-bgsave（此时的rdb.index与dump.rdb文件怎样？)；

同理，在auto-cron-bgsave进行的期间；config set appendonly no;
最后生成的（rdb.index文件怎样？）

看起来核心是rdb.index文件怎么生成的？
rdb.index由rdbSave函数生成，该函数可能save或者bgsave调用的，
无论哪种情况，都是rdb.index根据调用时的server.appendonly设置来生成。
rdb.index与dump.rdb绑定，都在rdbSave函数中生成。

save开启关闭:
- save开启关闭只修改saveparam，而触发只在serverCron中。

appendonly开启关闭：
- 开启只是open，并对相关的状态赋值
- doStopAof 后台flush/关闭文件

rdb.index文件时rdb和aof的粘合剂，但是rdb.index的产生、使用时间不一致，所以...



没开启aof:
<dbfilename>

开启了aof：
<dbfilename> <aof-inc> <aof-current-size> <next-opid>\n
<ssid> <applied-opid> <ssid> <applied-opid> ... <ssid> <applied-opid>\n

rdb.index什么时候消费??
doPurgeAof
loadOplogFromAppendOnlyFile
loadDataFromRdbAndAof
loadDataFromRdb

如果没有aof.index，则无法加载内容。

怎样清除当前server的oplog,applied_info等状态？

--------------------
测试案例：

- replication-psync

0. 启动master/slave
1. 按照确定参数设置 repl-diskless & repl-backlog 参数
2. 启动三个Write压力进程

> 建立复制关系
> 确认压力进程正在进行Write压力
> 测试psync:
    执行断链：如果reconnect==1，则在duration时间段之内，2s一次断掉与master之间的链路(multi;client kill <master host:port>; debug sleep delay;exec)
    确认数据一致：停止Write压力；按照1s/次,轮询10次，确认复制数据主从一致（debug digest)；
    执行cond检测

----------------------


aof的操作

start(open) : 打开aof_fd, 修改aof-inc.index,设置aof_state
stop: flush, bio close, 修改aof_state
split: stop, start, del
flush: 如果everysecond && no force && sync_in_progress，则放弃flush；write, 处理write error和short write；aof_fsync(fdatasync) 或者 aof_background_fsync(bio fsync)
del  : aof.index超过0.8M，触发疯狂purge，recheck 触发rdbSaveBackground（因为rdb.index可能对应很早的aof）；aof总量 > aof-keep(maxmem*2 或者 5G), purge to keepsize
purge: 考虑rdb.index, aof.index, server.aof_filename, aof-psync, opget clients, 创建bio purge任务。重新生成aof.index
purge-cron: 每30s del
split-cron: 每Hz 如果超过aof-max-size则split


相关操作：
rdbSaveBackground：

为啥有很多空的aof文件，能不能没有？ 
目前应该就是除了最后一个aof，没有空的aof文件;

如果1s之内产生了split了多次，会不会造成什么问题？
会造成同一个aof文件在同一时间打开超过一次，但由于write是不存在重叠的，因此也不会有什么问题！

aof max keeping size 可以配置。

如何在config set appendonly yes后触发bgsave

----------------------
rdb的操作

load
save
bgsave

为啥rdbSaveBackground可以在不判断aof开启的情况下prepareSave(flush, aofSplit)？

---------
从redis的代码上看，如果磁盘空间不足，会造成short write， errno = ENOSPC;这种情况最好ftruncate回退partial write。
atoi是一个很不好的函数，虽然用起来方便，但是无法检测是否真的符合数字规范，下面是参考：
char *endptr = NULL;
long pos = strtol(aof_position, &endptr, 10);
if(pos < 0 || *endptr != '\0' || errno == ERANGE) {

flush之后，close还需要异步吗？
---------------


::servers
[srv:{
    client,
    config_file,
    pid,
    host,
    port,
    stdout,
    stderr,
    config:{
        dir,
        bind
        port
        ...
        directive : arg
    }
    skipleaks
}]

---------------
psync 发起的opid是从哪里获取的？
server.next_opid

master和slave的opid怎么同步的？还是说各自维护各自的opid？
不管是aof还是replication，next_opid以opinfo命令为准。

如果slave没有开启aof，那么还能aof-psync么？opid又是从哪里获取的？
master会发送opinfo命令给slave，因此可以的！


如果master没有开启aof，那么还能接受aof-psync么？


为什么offset和opid需要分别维护，两者之间的相互作用是怎样的？
因为offset是master-->slave的流量记录，没有slave的情况下是不会记录的！
opid是aof模式的操作记录，另外opinfo是在cmd之后发出的！

server.next_opid重启怎么保存，purge了的怎么办，手动删除会怎样？


opapply会不会增加server.next_opid? 如果不增加那么在aof文件中怎么保存？在replication中怎么获取连续的oplog？复制难道只复制同一个serverid的？


appendonly yes->no->yes 这三个过程之后，server.next_opid怎么处理？是不是no的时候opid不增长？
卧槽，真的是这样的! 如果appendonly 为no，next_opid不增长。

oh nonono, 所以说config set appendonly no是一个非常危险的操作，会丢掉oplog。

配置文件里的appendfilename还有什么意义？

启动slave时，aof文件中的历史重要还是psync/fullsync结果重要？

分析场景：
master 关闭aof 无slave:
master 关闭aof 有slave
master 开启aof 无slave
master 开启aof 有slave

测试到了一个bug，复现步骤：
1. 启动master，启动aof，插入若干个数据
2. 启动slave，插入若干数据
3. 从info replication看出nextopid有问题。

redis-cli将结果重定向到文件不可行！因为redis-cli会修改结果。

配置里面的server-id与aof的server-id不一致会导致aof加载出问题吗？

ignored cmd会不会在monitor中出现？




|checkAndFeedSlaveWithOplogHeader #如果AOF_OFF也不会添加opinfo
|checkAndFeedAofWithOplogHeader 
    feedSlavesOrAofWithOplogHeader 
        如果复制 replicationFeedSlaves
        如果aof  
            initOplogHeader
            feedAppendOnlyFile


feedslaves不需要header？

opget, opapply, A->B->C，这种情况src_opid会变吗？
是会变的！！需要测试确认！！这样的话只能支持双中心！
需要fix

为什么作为2.0作为slave挂在1.0上不能形成一个有效的2.0master（aof文件格式不对！)

--------------------------

lpush 

aof 不开启，master无法正确过滤opid。next_opid没有正确过滤

opinfo 会不会放入到backlog中？


------------------------

如果app写slave，那么slave的next_opid将会陷入混乱！（其实复制也是一样的问题，复制怎么解决）



----------------

问题是：

- 由于不同中心的延时，bls无法保证时序，因此数据没有确定结果，那么upsql的情况呢？（与不同链接的时序无法保证类似）

---------------

分析测试failover造成的gap会不会影响数据转移

--------------

妈蛋，终于看懂了redis.tcl

API:

r blocking <0|1>
r reconnect 
r read 
r write
r flush
r channel
r deferred
r close 
r <others> 

实现：

dispatch_raw区分预定义命令与redis协议命令（others）不同的方法__method__xx
对于redis协议命令：

调用逻辑：

fileevent <fd> readable {<script> <fd> <args...>}
表示fd在出现读事件时会调用 {<script>..}

---blocking
1. 拼resp协议,发送
2. 同步读取回复

---nonblocking
1. 拼resp协议,同步发送


gets也是一个比较有意思的函数：不管在blocking还是non-blocking的fd都可以使用
如果nonblocking fd暂时没有一整行，gets将返回{}，但是不会获取部分结果。


redis::callback(id)是一个callback fifo
redis::state(id):  用于保存解析状态
{
    mbulk,
    bulk,
    buf,
}

readable:
    redis_reaable
        redis_call_callback {id type reply}
            uplevel #0 $cb redisHandle$id $type $reply
            redis_reset_state


type:enum {
    eof     : eof
    reply   : 收到一个完整的回复，通知callback进行分析
    err     ：收到错误回复
}

同步收到的是list of lists
已补收到的是list of string


回调函数原型：
proc xxxx {r type reply}


理解这行很重要：
interp alias {} ::redis::redisHandle$id {} ::redis::__dispatch__ $id

以上语句返回了一个函数别名，每次再用这个函数别名调用时，直接采用了dispatch函数调用，实现了类似对象的概念。


果然是tcl高手啊，300行实现了这么多！

-------------------------

server-id appendonly 这种对于数据的安全性异常重要的选项考虑不能动态修改，并且考虑动态修改可能或造成的问题。

--------------------------------

关于超时的过滤，因为超时可以在各中心独立进行，因此也没有必要同步DEL_BY_EXPIRE的命令（全渠道大量会有定时超时需求）

目前关于超时的类型，通过cmd_flag区分（共4bit），当前cmd_flag也仅用于表示DEL_TYPE。

可以考虑moray实现，或者redis内核实现。

考虑redis内核实现，增加过滤条件：skipexpire, skipeviction

matchflags delbyexpire|delbyeviction|delbyclient|all

关于更加复杂的语义解析相关的问题，以后扩展，目前仅支持 |

(!delbyexpire)&

为什么flags是链路级别的？什么时候设置的？

-----------------------------

robj->ptr???

-----------------
关于oprestore的作用：

oprestore能够在保持master数据不变的情况下，重新propagate restore*foo*replace命令，可以用于缺失aof-binlog的情况下恢复某个key。
这个接口留着，运维的时候可能会用到。




# upredis-api-c


- README有点业余啊
- upredis_log_set_handle? wtf!!
- open_conn与 connect connect_with_auth connect_with_timeout??
API范式有点混乱！！
- free_reply_object?为什么不直接free_reply
- set_timeout? connect超时控制了吗？
- 长短链接的原理上的区别？

使用上的迷惑？

set_option的，key，value（类型）

为什么不使用sys/queue，而放入无关的tailq.h

另外为什么设计那么多的vcommand，command

设计文档呢？

为什么拿到的不是直接的hiredis？

不依赖于commons-pool这样的组件的话，pool策略是什么样的呢？

minIdel，maxTotal，block when exhausted, evictor？

testOnBorrow, testOnIdle, testOnReturn

reload操作涉及的问题

好奇葩啊，居然提供了直接链接指定ip，port，timeout，passwd的接口

为什么把svr_info和passwd与其他的option区分开来？不能统一到option中？

reload操作的话，哪些东西能reload，哪些东西不能reload？

Wlog什么的会不会影响性能，要不要perf或者gperf一把。


------------------
options:
struct upredis_option;
upredis_option_init(struct upredis_option *opt);
upredis_option_set(struct upredis_option *opt, int k, const void *v, int vlen);
upredis_option_get(struct upredis_option *opt, int k, void **v);
upredis_option_deinit(struct upredis_option *opt);


conn:
struct upredis_conn;
upredis_conn_open(struct upredis_conn *conn);
upredis_conn_open_persist(struct upredis_conn *conn);
upredis_conn_open_auth(struct upredis_conn *conn)?
upredis_conn_open_persist_auth?
upredis_conn_close(upredis)

handle:
struct upredis;
int upredis_init(struct upredis *uprds, struct upredis_option *opt);
int upredis_init_from_cfg(struct upredis *uprds, char *cfg);
void upredis_deinit(struct upredis *uprds);
void upredis_set_log_callback(struct upredis *uprds, logcb);

----------------------

设计目标：

- 后端接多个upredis-proxy，提供负载均衡、连接池、高可用功能；但是不提供分片功能，分片功能有upredis-proxy提供


- 单个redis，提供连接池功能？
- 多个redis，提供分片功能
- 多个redis，提供分片&连接池功能
- 多个proxy，提供连接池，负载均衡，高可用

关于高可用和分片：有待讨论

--------------------------------
- 目前hiredis好像是针对单个redis的链接功能，其他的类似 JedisPool，ShardedJedis，
    ShardedJedisPool，JedisSentinelPool的功能都么有！

- upredis实际上是做了hiredisPool，添加了负载均衡和高可用，后面只能链接proxy或者单个redis
    （单个redis，直接用hiredis; 多个redis，由于没有分片，所以也没有用）



--------------------

几个不能理解的问题：
1. 为什么提供直连接口
2. 为什么提供长连接
3. 重构是否需要保持API一致

------------------------

如果让我重新设计：

1. 全部短连接使用
2. evictor有必要，因为idle的健康状态堪忧
3. reload 只能用reload option


-----------------------------

计划： 先把1.1.0上的已有的issue解决，发个patch版本，然后再考虑重构问题,再发个大版本，包括API变动和其他.


----------------------------
review代码吧！

- 卧槽，redisConnectWithTimeout？redis能很优雅地控制connect超时！！！
- 使用了cdb-pub的日志模块，内存模块，dbpm模块
- 含有三种连接： 长连接，短连接，自定义连接
- 用了两类锁：svr锁->conn锁->计数锁；
- 获取短连接: 先选择svr;然后选择svr->free_conns.head；如果没有，则创建一个conn；如果创建失败，则换下一个svr；
- 关闭短连接：放到池中或者删除（如果svr已经被删除，或者conn出问题了），并释放资源；
- 获取长连接：先选择svr；然后创建persist_conn，并添加到svr->persist_conns;如果创建失败，则换下一个svr；
- 关闭长连接：直接从svr中删除，释放资源；
- 获取自定义连接：malloc upredis_conn, 直接调用hiredis获取，并设置rctx
- 关闭自定义连接: 直接释放资源
- 关于密码：支持无密码，本地密码，dbpm密码；加密方式支持无加密，SHA256
- reload操作: 支持对svr_info和passwd进行reload
- 关于隔离恢复操作：
    隔离：取连接的时候，如果svr出错了，那就计算一次错误；如果累计的错误数量超过了阈值，那就割了吧；
    恢复：每次open都恢复一次,对于长连接还要rebalance一下；先把状态不ok的svr清理下链接，然后同步地连接一把redis,成功的就恢复。
- 为啥我还没有看到偷换链接的操作:
    每次操作都会尝试替换恢复和替换连接（！！)，这个性能消耗还是不少的！



-----------------
需要重新梳理下长连接和自定义连接存在的意义；


-------------
隔离操作：
每个命令都会检测，并且计数隔离；如果正确使用连接的话，也没什么问题；
恢复操作：
open_conn, open_persist_conn时，只要当前有需要recover的svr，那么遍历并找到svr，对其进行recover（会先删除freeConns)

问题为什么在隔离svr的时候，没拿走的连接直接销毁，如何处理已经被拿走的连接？ 貌似没有处理
那么如果这部分连接还回来怎么办？

如果在reload中删除了某个svr，并且该svr被隔离，那么该svr的游离连接close时会发生什么？


被隔离的svr会被怎么操作？free?: no, 空闲连接被清除，状态被置为SVR_ERR
被reload删除的svr又会怎样？free？free_conns被free，used_conns, persist_conns没有都被free，svr被free。


所以说返还连接的时候，有可能svr已经不存在了, i.e. conn->svr == NULL

隔离回复的标志是svr-status，fail_cnt虽然记录的次数。

经过以上考证，在清零fail_cnt可以更加合理地抵抗网络抖动！

回头思考api-java能不能做类似的事情：发现api-java无法做到，因为直接拿到的就是Jedis连接，而Jedis连接的操作不会通知api-java，因此做不到清零。这又暴露出来一个问题：网络抖动造成的fail_cnt会在api-java中累积，从而造成隔离（其实是不太合理的）retureResource是否应该清零呢？？？


------------------

上次关于proxy后端超时问题引发的思考：
- redis pipeline是处理完了一个pipeline之后一起发送结果吗？还是说一部分一部分读，然后再一部分一部分写？
- 如果redis的一条线路上的一个大pipeline导致处理时间很长，会不会导致其他的线路starve？如果会starve，如何避免这种starve？

- 为什么twemproxy使用单链接？好像也支持多连接？
- 如果支持多连接，那么在某个链接断掉或者超时，那么积压在该链路上的请求是否转移到其他链接？
- 对于性能来讲，其实单链接不会比多连接差，但是如果多连接的话？

- pipeline的接收时尽量接收的！

------------------------
- 我擦，居然没有权值
- reload操作只会删除svr，增加svr；不会删除used_conns，不会重新负载长连接（那么所谓的重新负载的作用在哪里？）
- 长连接在什么时候会进行连接替换；长连接，openconn触发了svr恢复，
- rebal的意思是在recover的时候会

- 如果应用使用方式为command,command, getreply, getreply这样的话，有可能就会因为偷换链接造成结果混乱！但是如果command，getreply这种方式就不会有什么大问题


综上： 偷换链接只有在recover时才会在长连接侧发生，偷换的思路：只要当前的command/open触发了恢复，那么当前链接被重新负载到别的svr！
另外在偷换链接的时还是采用同步生成链接！可能出现非必要的超时

另外评估重新负载的必要性！

为什么只有触发recover的那个长连接才有必要rebal？还是说rebal是附带功能？


-----------------------
关于version
每次upredis_command都会进行版本检查，如果当前长连接的版本号小于upredis版本，那么就会重新负载，偷换链接,偷换链接的动作实在command之前做的，因此只要是command之前的reply都已经获取完成了，也不会出什么问题；
所以说reload会进行rebalance操作！

free_conns & used_conns的版本有效果吗？没有
为什么recover动作不会触发版本号变更？因为没必要被！

-------------------------
_uprds_create_conn_from_svr->_uprds_create_conn


实现思路：
1. recover中使用的同步操作换成非阻塞！

那么其他的同步操作：

rebal中使用的同步操作？
rebal策略：
    随机一个svr:e，如果e与当svr:s同一个，则不用rebal；否则
    e作为起点，循环遍历队列，从e中创建一个链接tmp（同步操作）；
    然后用tmp替换当前ctx

possible issue：
该issue同时存在于长连接的reload和recover操作中：
- 如果reload添加了一个不可达的svr，由于reload操作触发长连接rebalance，而rebalance操作会遍历svr尝试创建新的连接，而该操作同样有可能造成阻塞；

但是由于基本上该操作是由于应用造成的，而且本来创建连接也会出现阻塞，现象也容易观测到，所以也不算是个issue。


经过分析可知：其他操作不会引发与宕机类似的问题，因此只需要conn ping的时候执行非阻塞操作就好！



----------------------------

方案评审的一些问题：
1. lib多线程可能会带来的一些问题，主要是给多进程的程序带来了哪些风险，比如说errno，信号量
:: 从搜索结果来看，轻易是找不到相关的信息的，只能通过经验和实践以及源码分析来解决以上问题。

2. zdogs是如何考虑多线程的问题的？
:: 暂时不打算分析zdogs的源码来解决这个问题


------------------------------------

关于为何要每隔5s就reset一次，能不能不reset，能不能通过次数控制轮转频率？

每隔5秒reset一次是因为需要控制状态机的流转频率（每个svr 5s之内最多状态机轮回一次，状态
机轮回一次是需要比较多的资源的：创建socket，建立连接，发送报文等）

不能不reset：因为不reset的话无法开启下一轮状态轮转；如果要控制轮转的频率，那么就必须通过
时间来控制。

--------------------------------------
使用状态机的问题：
- 不能立马恢复svr，需要好几笔交易触发
- 如果只剩一个svr的话，需要好几次open才能触发

现在我怎么觉得，通过降低connect的超时时间来控制恢复也不失为一种好办法。



---------------------------------

系统测试记录：

有很多案例没有COND，也就是只有测试没有预期，这样的话除了能测是否core，并不能测试其他点。

有些测试案例应该放在FAQ中！

1.  test_init
预建连接10
建立连接数量1000，连接数量为1000

2. test_svr_down_on_init
预建连接不成功，则放弃
多次open之后，down svr被隔离

3. test_short_basic
测试短连接基础

4. test_isolate_cnt
测试隔离触发的次数

5. test_persist_basic
测试长连接基础

6. test_double_close
测试double close一个连接

7. test_svr_down
测试svrdown情况下的ha功能

8. test_svr_isolate_recover
测试svr down然后up之后的隔离恢复功能

9. test_reload
reload的多种情况，具体参考注释

10. test_dbpm_update_passwd
更新dbpm密码









# upredis-api-java

#9 fix mvn test fail

mvn test与make test执行的命令不一样！

make test执行的是TestRunner

mvn test:
- Test Runner为插件maven-surefire-plugin
- maven-surefire-plugin的test目标会自动执行测试源码路径（默认为src/test/java/）下所有符合一组命名模式的测试类。这组模式为：
**/Test*.java：任何子目录下所有命名以Test开关的Java类。
**/*Test.java：任何子目录下所有命名以Test结尾的Java类。
**/*TestCase.java：任何子目录下所有命名以TestCase结尾的Java类
- 跳过测试 mvn package -DskipTests  
- 选择特定的测试案例 mvn -Dtest=TestSquare,TestCi*le test

我的问题出在maven默认的行为不能共享BaseTest代码，解决办法：
https://stackoverflow.com/questions/174560/sharing-test-code-in-maven#174670

- jedis中基本测试环境搭建是通过Makefile进行，jedis使用Makefile部署/撤销环境，调用mvn

#4 add tutourial

查看jedis，发现jedis并没有在src中添加示例代码
test中示例了一些用法，更多的示例是通过wiki给出的。

#5 机器宕机造成api调用耗时太久

解决方法：
1. 参照clogs的策略，但是需要非阻塞发送ping报文。
2. 启动线程做检测！
3. 搜索java redis 负载均衡


搜集信息：
1. 可能可以通过pipeline来做（作者讲的）！
https://stackoverflow.com/questions/11338936/does-jedis-support-async-operations
刚刚分析了下，使用pipeline依然会阻塞！

2. issue中表示在3.0中会支持async特性，但是目前还没有看到3.0的计划2011-2017 still work in progress....
https://github.com/xetorthio/jedis/issues/241


3. 关于对Jedis做load-balance的工作已经有一个质量很差的实现：
https://github.com/CodingDance/JedisBalance

!!!也是基于线程的实现。

TODO：

- 关于Java的IO非阻塞异步的知识
- Jedis中的其他类的用法深入了解


NIO
We're still studying future vs callback.

Yes. Actually I feel very tricky to implement with RxJava because most of commands returns single value, and there're many kinds of return types.
But I also agree that callback could be hell, and Java Future (under Java 8) is not fully async, so I'll give it a try.

从以上讨论至少了一看到以下信息：
1. jedis尚未支持async特性
2. 实现异步特性至少含有以下方法：
- netty
- vert.x
- rxjava
- future
- callback
- NIO
- lettuce

oh my god! mess like hell

并且我感觉应该不太好做！妈蛋，可能还是要用线程方法！一觉回到解放前


能不能直接利用client的命令，但是getresult?


#7 提供原生jedis服务

既然要提供jedis服务，那么必须了解Jedis原生提供了哪些东西喽!


直接看吧(3-4w)！


Jedis->BinaryJedis + JedisCommands, MultiKeyCommands, AdvancedJedisCommands, ScriptingCommands, BasicCommands, ClusterCommands, SentinelCommands, ModuleCommands 

ctor:
  Jedis(JedisShardInfo shardInfo) 支持分片
  Jedis(URI uri) 支持uri指定服务器信息
  支持ssl


methods:

- 每个命令都会先检测是否pipeline or multi
- 命令基本都是client在执行，Jedis简单地对这些命令进行封装（并返回值）


>> so client does all the hard work


BinaryJedis -> BasicCommands, BinaryJedisCommands, MultiKeyBinaryCommands, AdvancedBinaryJedisCommands, BinaryScriptingCommands, Closeable

ctor:

- 区分了sotimeout和connectiontimeout
- 依然支持shard和uri

variable:
 client
 pipeline
 transaction

methods:

- 依然是client干活
- 与Jedis最大的区别在于输入输出参数都是byte，调用client函数为直接命令而不是sendCommand
- checkIsInMultiOrPipeline的作用是检查当前的jedis模式并抛出异常

>> wow! 代码真他妈多，但是不理解为什么需要BinaryJedis，我们又不使用。


Client -> BinaryClient + Commands:

ctor:

支持ssl，但是URI在BinaryJedis中已经处理过了！

methods:

- 基本都在使用BinaryClient中的方法，但是对参数进行了safeencode
- sendCommand 居然是继承的！

>> 又是个代理商


BinaryClient -> Connection:

ctor:

- 全部代理到Connection中

variable:

  isInMulti 是否在multi模式
  password  密码（重连时会用到）
  db        数据库
  isInWatch watch模式

methods:

- 实现了很多方法，但都调用了sendCommand/sendEvalCommand

>> again 承包商

Connection + Closeable:

ctor:

variable:

private String host = Protocol.DEFAULT_HOST;
private int port = Protocol.DEFAULT_PORT;
private Socket socket;
private RedisOutputStream outputStream;
private RedisInputStream inputStream;
private int connectionTimeout = Protocol.DEFAULT_TIMEOUT;
private int soTimeout = Protocol.DEFAULT_TIMEOUT;
private boolean broken = false;
private boolean ssl;
private SSLSocketFactory sslSocketFactory;
private SSLParameters sslParameters;
private HostnameVerifier hostnameVerifier;

methods

connect: socket连接，准备好inputStream，outputStream
sendCommand: Protocol.sendCommand最后基本是调用的静态方法
getStatusCodeReply: 阻塞读取回复，然后encode

？怎样保证结果已经读取完全, 特别是像pipeline这种使用方式？
Protocol.read怎么进行消息分割的？

>> connection中关于IO操作以及强制类型转换还是不太容易看明白！

Protocol

ctor:

- Protocol不能实例化

variable:

- 大量的默认值，constants

methods:

sendCommand: 按照redis协议组合命令。
read: read并不是trival的inputStream.read，该read表示处理一个回复消息;
read 给根据firstbyte判断回复的类型，然后采取不同的策略读取结果。


- 关于connection中的疑问释然了：
tcp流式数据模型在c/java中没有区别.
byte[]并不能智能地转换为任意类型，而是因为采用了不同的process方法。

>> 比较有趣的是Enum的特性，enum看起来像是对每一个枚举都有一个对象


----------------------------------------
JedisSentinelPool

ctor:

先遍历Sentinels，获取当前masterName集群的master；然后向每个sentinel注册
masterListeners，如果sentinels做出了切换的决定。pool将收到sentinel的切换
通知。

variable:

masterListeners = new HashSet<MasterListener>();

method:

提供getResource, returnBrokenResource, returnResource三个标准的接口


MasterListener -> Thread:
setDaemon
start

ctor:

variable:

method:

run 

订阅sentinel的信息推送，并且如果exception之后，sleep 5s再次尝试订阅

如果出现failover，会重新initPool

所以这个引入了PubSub这一特性！


>> 虽然sentinelPool能够做到failover，但是依然不能对多个pool进行管理。

ShardJedis -> BinaryShardedJedis + JedisCommands, Closeable :


我擦不能这么分析，后面的复杂。

- 如何做到一致性哈希的？
- 如何做到多线程安全的？因为存在多个线程同时哈希到一个Jedis，然后同时发送?
- 与SharedJedisPool的区别?

貌似每个shard都有一个对应的Jedis，然后呢shardedJedis与Jedis一样，并不是
线程安全的；但是对于单线程而言，SharedJedis聚合了多个Jedis，然后分片，单线程
不会同时访问同一个Jedis，因此不存在多线程问题。

>> 总而言之是采用了一致性哈希来将多个key分配到多个jedis中。

SharedJedisPipeline：

>> 横向扩展Jedis并且使用其Pipeline功能。

ShardedJedisPool -> Pool<ShardedJedis> 

ctor:

variable:

method:

SharedJedis的池


---------------------
至此，Jedis的代码粗略分析完成。

问题1： 能不能通过JedisBalancer直接链接redis？

暂不支持！但是可以采用SharedJedisPool

问题2： 能不能组合SharedJedisSentinelPool? 提供一个分片的主从JedisPool？

fair enough！

但是按照钱包的实现思路实现就可以了！

------------------------

回到最开始的问题：能不能非阻塞发送Jedis报文？

java的非阻塞编程与C的模型一样；但是Jedis本身并不支持，所以即使能够通过socket非阻塞发送

开个线程喽！


---------------------

方案：

1. 开启一个线程做recover & isolate
2. getResource不做recover isolate



----------------------
关于pom中的依赖问题：




#upredis-proxy

# 主体设计

## 事件库：
- 处理顺序为ERR>READ>WRITE所以会出现：
1）redis断链之后，执行的是core_err->core_close->server_close；
2）如果有一个大的pipeline，proxy可能会一致读取，导致无法及时将请求发送到redis（大pipeline超时）
3) server突然断链那么导致正在等待回复的客户端收到server

- READ常驻/WRITE事件需要的时候添加

- libevent的rw事件可以分别设置为两个不同的event
  nc的事件机制中fd与cb(core_core)一一映射，core_core根据conn,events 按照E->R->W处理事件
  每个conn通过不同的recv,send,close函数指针定制不同的ERW行为。

- loop

a) 处理reload
b) event_wait   # 默认stats_interval 10ms; ctx->max_timeout也为10ms；
c) handle_accumulated_signal
d) core_timeout
e) core_before_sleep

## 消息

### 解析

- 解析过程的复杂性在于msg分散到多个事件循环读取，msg分散到多个mbuf存储，一次读取的数据量可能包含X.Y个msg
- `conn->rmsg`用于保存正在读取、解析的msg（考虑msg分到两个事件循环读取）
- recv->recv_chain->parse->parsed->recv_done->forward 这个过程都是在STAILQ_LAST(msg->mhdr, mbuf, next)上进行的
- parsed过程完成了mbuf, nbuf, msg, nmsg的衔接

```
msg_recv
    while (conn->recv_ready)  # recv_ready==0的情况： EAGAIN; EOF; ERROR
        msg = conn->recv_next # 新msg或mbuf残余的nmsg
        msg_recv_chain  # 读满一个mbuf；对mbuf命令逐个msg解析；解析之后路由到对应的svr

msg_send
    while (conn->send_ready)
        msg = conn->send_next   # siq的迭代器
        msg_send_chain # 一次sendv；sendv之后对mbuf&msg逐个finalize

```

消息流转：

Client  READ: 读取msg; msg --> coq, msg --(forward)--> siq；添加sconn写事件
Server WRITE: siq --> msg; 发送msg；msg --> soq；
Server  READ: 读取pmsg; 与soq.first建立关联；msg从siq出队；添加cconn写事件
Client WRITE: coq --> msg；发送pmsg；soq -->；释放msg--pmsg

解析:

通过状态机实现: tokennize，state，流式, DFA

1)repair：如果token跨两个mbuf，那么将这个token切断到另一个mbuf；
2)again: token未被切断，但mbuf已经被扫描完成
3)ok: mbuf在被扫描完成之前，已经解析到一个完整的msg；如果一个msg跨越两个mbuf，那么该
    msg将悲切分为两个mbuf（i.e. msg与mbuf是一对多的关系）


路由和分片：
conn->recv_done # msg 读取解析完成的后续动作
1) 过滤： quit-在client所有reply收到后关闭连接，auth之前命令不forward，ping命令不forward，管理命令直接回复客户端不支持
2) forward：如果不需要forward，直接回复客户端；如果需要forward，则路由到指定的svr

## 异常处理

几个标记的说明

CLIENT EOF:
由于无法区分客户端到底是close还是shutdown_rd，因此客户端断链当做shutdown_rd处理：
- 由于第二次向close的客户端send会引发EPIPE，因此proxy应该处理EPIPE错误
- 客户端close时，可能msg还没有完全写完，这部分消息将被丢弃
- 半关闭状态的客户端连接还能继续接受svr发来的rsp，因此proxy应该继续向client发送rsp

处理流程：
conn_recv给链路打上eof标记;conn->recv_next丢弃不完整msg；conn停止read；

SERVER EOF:
服务端EOF说明server已经不正常(crash或者错误了)，因此立即关闭链路。

处理流程：
conn_recv给链路打上eof标记;conn->recv_next丢弃不完整msg，标记链路done；conn停止read；
接着由于链路done，关闭server链接:
- 标记siq, soq中的msg为err
- 更新server->next_retry
- 标记server为dead 
- close

SERVER ERR:
过程同SERVER EOF

CLIENT ERR:
立即关闭客户端链接：
- 抛弃非完整req 
- 已经forward的req标记为swallow

协议错误：proxy,redis都直接关闭链接
命令不支持：redis回复-ERR unknown command 'xxx'; proxy将直接关闭链接
- 将conn标记为err
- 客户端/服务端链接被关闭

## 超时处理

core_timeout 根据当前的rbtree计算event_wait等待的时间

如果req超时：
    - 标记conn为ETIMEOUT
    - 断开req所属的链接

为了处理connect超时，sever connect时会向tmo中添加一个fake msg:
- 如果connect正常：连接之后删除该fake msg
- 如果connect超时: fake msg超时，触发断链
以上操作避免了不可达的情况，connect超时需要很长时间


## signals

日志等级up          sigttin
日志等级down        sigttou
重新打开日志文件    sighup
退出                sigint,sigterm(15)
开启reqlog          sigusr1
reload config       sigusr2
coredump            sigsegv


## 断链重连

server的初始化过程：

server_pool_init:
    conf_pool_each_transform:
        server_init:
            conf_server_each_transform: 根据conf初始化server struct
    server_pool_run: 初始化一致性哈希结构

server的链接建立过程：

core_ctx_create:
    server_pool_preconnect:
        server_pool_preconnect_fn:
            server_each_preconnect:
                server_connect:socket, setnonblock, setnodelay, event_add_out, connect

dead之后重连server
core_before_sleep: 
    server_reconnect_check:
        server_connect:socket, setnonblock, setnodelay, event_add_out, connect

autoeject之后重连
req_recv_done:过滤，路由接受到的req msg
    req_forward:
        server_pool_conn: 选择server,选择conn，链接conn
            server_connect:socket, setnonblock, setnodelay, event_add_out, connect

- server的建链过程发生在初始化preconnect，定时检查，req_forward时
- req_forward在server->dead时不connect，并且errno为ETIMEOUT
- reconnect只有在server->dead时进行重连
- dead表示fake eject：如果auto eject，直接eject;否则dead
- 恢复过程为：
server_pool_conn:
    server_pool_update: 根据server_retry_timeout设置的next_rebuild，更新continuum

对于非auto_eject而言，每次断链都会造成server_dead；


综上：
- preconnect，初始化链接(dead=0)
- 断链之后，每个server_retry_timeout之后重连（被动|auto_eject_hosts, 主动|!auto_eject_host)


对于slave创建链接的启发：
- 设置slave的dead=0, 初始化链接，而且preconnect **WITH TIMEOUT**
- 断链之后，每隔server_retry_timeout之后重连

在preconnect成功之前，proxy收到了req怎么办？:
req_recv_done:
    req_forward:
        server_pool_conn: 返回一个connecting或者connected的链接
            server_pool_server
            server_conn
            server_connect
        enqueue siq:

综上： connecting的链接等同于链接好的链接

对于slave链接的启发：
- 发现新的slave之后preconnect
- slave dead 断链之后，每隔server_retry_timeout重连



隔离操作：

trick：server_close实际上的意思是conn_close;

server_each_preconnect:connect失败，关闭连接
    server_close: 如果conn->sd==-1,直接销毁conn;否则，销毁消息队列，然后再销毁conn
        server_failure: 
            server->dead = 1; 或者 server->failure_count++

server_reconnect_check:connect失败，close连接
    server_close

server_pool_conn: connect失败，close连接
    server_close

connection_is_drained:??
    server_close

core_ctx_destroy:
    server_pool_disconnect
        server_pool_disconnect_fn:
            server_each_disconnect:
                conn->close:
...



恢复操作：
a) auto_eject_hosts:
到了next_rebuild之后，对当前需要rebuild的servers，update continuum；
这样的话server被重新添加到可用svrs中

b) !auto_eject_hosts:
到了server->next_retry之后，发起reconnect操作，reconnect成功之后dead=0

关于dead的考究:
server_close:
    server_failure: 
        server->dead = 1; 或者 server->failure_count++
所以对于connection大于1的server，只要一个连接出现错误，则判断server dead是不合理的！

## 密码管理

大体思路： 加密密码>明文密码>dbpm

proxy密码配置：
redis_auth: foobared
redis_auth_s: 1b58ee375b42e41f0e48ef2ff27d10a5b1f6924a9acdcdba7cae868e7adce6bf
dbpms:
    - IP1:PORT1:db1:usr1
    - IP2:PORT2:db2:usr2

实现思路：

conn->need_auth  配置了redis_auth后，链路被标记为need_auth
conn->authing    发送了auth命令之后，链路被标记为authing
conn->dup_auth   pipe_q非空，然后又来了一个auth报文，则链路被标记为dup_auth；
                然后redis_reply时回复DUP_AUTH之后，又将dup_auth标记撤除
AUTH处理流程:
req_recv_done:
    if (msg->noforward):
        req_make_reply:创建reply结构
        msg->reply:(redis_reply)
            如果dup_auth则回复DUP_AUTH
            如果need_auth则回复NEED_AUTH
            如果是auth命令则将auth命令传递到对应的conn:redis_handle_auth_req

        if msg is ping:
            reply pong

redis_handle_auth_req:
    dbpm_select:
        dbpm_connect:
        发送dbpm请求

按照密文>明文>dbpm的级别对比密码


dbpm密码支持：
- conn->usr_auth表示sha256编码的密码，用于与返回的dbpm密码对比
- noforward的命令包括：auth之前的所有命令；ping; auth; auth_s;
- noforward的命令都会直接由conn->reply(redis_reply)处理
- authing过程中的命令全部放在conn->pipe_q中


---- 
nutcracker的策略：
前端的auth命令发送给proxy进行验证；
后端的链接通过add_auth认证；并且对于auth的结果并不判断是否正常。

## 监控管理

之前已经分析过，收到客户端stats命令之后，mgm转发、聚合stats信息，然后再返回客户端
json报文。


分析stats线程与worker线程之间的数据交换，分析为何出现coredump:
stats监控的数据：

```
pool stats:
client_eof          "# eof on client connections"
client_err          "# errors on client connections"
client_connections  "# active client connections"
server_ejects       "# times backend server was ejected"
forward_error       "# times we encountered a forwarding error"
fragments           "# fragments created from a multi-vector request"

server stats:
server_eof          "# eof on server connections"
server_err          "# errors on server connections"
server_timedout     "# timeouts on server connections"
server_connections  "# active server connections"
server_ejected_at   "timestamp when server was ejected in usec since epoch"
requests            "# requests"
request_bytes       "total request bytes"
responses           "# responses"
response_bytes      "total response bytes"
in_queue            "# requests in incoming queue"
in_queue_bytes      "current request bytes in incoming queue"
out_queue           "# requests in outgoing queue"
out_queue_bytes     "current request bytes in outgoing queue"

```

看样子upredis-proxy只是修改了proxy的stats信息获取方式，没有修改stats监控的数据种类：

stats_server_set_ts
    _stats_server_set_ts
        stats_server_to_metric:
        stm->value.timestamp = val


### 总体设计

stats有shadow, current, sum三个stats_pool[]: sum = shadow + current，其中shadow, sum从属于stats aggregator线程
current从属于worker线程，当current move到 shadow时需要使用shadow_lock锁.

struct stats：
- shadow，current，sum
- 各种string
- 链路相关ns_conn_q, s_conn_q， next_retry等
- stats信息数组[] client_eof, server_eof, fragments等

struct stats_pool:
    name
    metric: stats_metic[]
    server: stats_server[]

struct stats_server:
    name
    metric: stats_metric[]

struct stats_metric:
    type
    name
    value

typedef enum stats_type:
    STATS_INVALID,
    STATS_COUNTER,    /* monotonic accumulator */
    STATS_GAUGE,      /* non-monotonic accumulator */
    STATS_TIMESTAMP,  /* monotonic timestamp (in nsec) */
    STATS_SENTINEL


stats aggregate:

stats_rsp_recv_done:
    stats_aggregate:
        locK shadow_lock
        foreach pool:
            stats_aggregate_metric
            foreach server:
                stats_aggregate_metric
        unlock shadow_lock

stats swap:在server处于稳定状态时，每个evloop都进行统计数据交换;server在reloading时不
交换stats信息

stats_swap:
    array_swap(current, shadow)
    stats_pool_reset(current)


stats的初始化和清理：

{core_worker_create, core_mgm_start, core_worker_recreate}
    stats_create:
        stats_pools_create
            stats_pool_map: 分别初始化current, shadown, sum
                stats_pool_each_init
                    stats_pool_init: # 初始化 pool metric
                        stats_pool_metric_init
                            stats_metric_init
                        stats_server_map # 初始化svrs metric
                            stats_server_init
                                stats_server_metric_init: #初始化或者继承统计值
                                    if (GAUGE && !recount)
                                        继承server初始化之前的数值！
                                    else 
                                        stats_metric_init


stats聚合与回复:

创建buf：
stats_create
    stats_pools_create
        stats_create_buf：根据当前的server，slave信息预先buf大小


## 动态生效

ctx->reload_sig 发起reload的标记（kill -SIGUSR2; reload_redis; +switch-master)

ctx->reload_delay: worker try reload again? 标记为reload2，排在当前reload之后的reload请求

ctx->failover_reloading: 

ctx->state:
    CTX_STATE_STEADY,
    CTX_STATE_RELOADING,
    CTX_STATE_RELOADED,

ctx->stats_reload_redis
    STATS_RELOAD_INIT = 0,
    STATS_RELOAD_START, 
    STATS_RELOAD_WAITING, 
    STATS_RELOAD_OK, 
    STATS_RELOAD_FAIL, 

ctx->req_stats
    STATS_REQ_INIT,
    STATS_RELOAD_REDIS,
    STATS_MIGRATE_START,
    STATS_MIGRATE_DOING,
    STATS_RELOAD_REDIS_MIGRATING,
    STATS_MIGRATE_END,
    STATS_STATS,
    STATS_STATS_ALL,


core_loop
    core_before_sleep
        core_reload_check
            if (ctx->stats_reload_redis == STATS_RELOAD_START
                if ctx->state != CTX_STATE_RELOADING:
                    config_reload_redis
                        server_pool_init replacement_pools
                        server_pools_kick_replacement
                        ctx->state = CTX_STATE_RELOADING;
                    ctx->stats_reload_redis = STATS_RELOAD_WAITING;
                else # reloading时，又来了reload命令，即reload2
                    ctx->reload_delay = 1

core_loop
    core_timeout
        core_timeout_reply: 对于超时mgm消息，回应-err timeout
            if (st->alive_cnt == st->cmd_suc_cnt + st->cmd_fail_cnt + st->cmd_timeo_cnt
                && ctx->reload_delay) # 超时，reload2上位为reload
                ctx->reload_delay = 0
                ctx->reload_sig = 1

core_loop:
    if (ctx->state is CTX_STATE_STEADY or CTX_STATE_RELOADED)
        stats_swap
    if (ctx->state is CTX_STATE_RELOADING)
        if server_pools_finish_replacement
            ctx->state = CTX_STATE_RELOADED
        else
            timeout = 10ms

stats_loop
    if worker:
        stats_before_event_wait
            stats_check_reload_redis_finish: 如果WAITING、INIT、START，则返回；如果OK, FAIL则回复相应结果
            
    if master && ctx->reload_sig
        stats_failover_reload:
           if (ctx->req_stats != STATS_REQ_INIT)
               ctx->reload_delay = 1
           else 
               ctx->failover_reloading = 1
               stats_req_forward

stats_rsp_recv_done
    stats_rsp_forward
        stats_make_rsp

stats_req_recv_done
    stats_req_forward
    stats_req_check
        if (msg->type == MSG_REQ_REDIS_RELOAD_REDIS)
            ctx->reload_delay = 1; #如果mgm正在执行其他管理命令，来了reload请求之后，reload排队(reload2)

stats_server_close:
    if (ctx->reload_delay)
        ctx->stats_reload_redis = STATS_RELOAD_START;

### mgm进程：

>>> mgm线程
mgm线程在几乎不对reload有任何影响，只用于响应shutdown命令

>>> stats线程
如果发现当前ctx->reload_sig，则将reload信号分发到各worker；
（分发了reload信号之后，收集reload响应的工作在rsp_recv_done中处理）

>>> monitor线程
侦听+switch-master消息，修改配置文件，将ctx->reload_sig置为1

### worker进程：

>>> stats线程
收到了reload req，则启动reload(ctx->stats_reload_redis = STATS_RELOAD_START)
worker与mgm之间的链路断掉时发现有reload2，则启动reload

定期检查reload是否完成(ctx->stats_reload_redis为OK, FAIL), 并且将结果回复给mgm进程(WAITING)

>>> worker线程
检查reload是否启动(ctx->stats_reload_redis处于STATS_RELOAD_START)如果启动,则执行reload(config_reload_redis)
每个loop都检查reload过程是否完成；如果完成则ctx->stats_reload_redis = STATS_RELOAD_OK


### reload与stats
- reload过程中不会执行stats_swap，也就是说stats信息被冻结了！
- reload完成之后，stat_pools将被重建

隔离时，被隔离的server丢失几笔交易？丢失当前在server上排队的所有交易，所以说：若干笔！

---------------------------
## 异常处理

recv:
core_core
    core_recv
        conn->recv(msg_recv)
            msg_recv_chain
                conn_recv
                    while (eintr)
                        rc = recv
                    conn->recv_ready = 0 if (eagain,err)
                    conn->err = errno if (err)
                    return (err, eagain, n)
    if (core_recv err || conn->done || conn->err)
        core_close
            conn->close
                server_close or client close
### conn异常

#### conn->done

conn->done标志着该conn需要被关闭。

- 对于client来说，conn->done表示client conn已经关闭了write half，并且client conn所有消息都已经
  已经收到了回复

- 对于server来说，只要server eof, rsp stray, 则conn->done，因为除非server异常，否则server是不会主动断链的！

#### conn->err & conn->error

理某个链路的过程中出现了错误，导致链路需要关闭，就可以将errno赋值到conn->err，同时将conn->error置为1

#### conn->eof

链路收到了eof，但需要注意的是client与server对eof的不同处理方式

### msg异常

#### msg->err & msg->error:

标记着该msg在发送的过程中出现了err，需要将向客户端回复msg->err，对应的errstr

core_timeout
    if (msg->error || msg->done)
       skip

server_close
    foreach msg in siq
        swallow or noreply or ...
        msg->done = 1
        msg->error = 1
        msg->err = conn->err
    foreach msg in soq
        swallow or ...
        msg->done = 1
        msg->error = 1
        msg->err = conn->err
        event_add_out(msg->owner)
    discard conn->rmsg
    server_failure
    server_unref
    close(sd)
    conn_put

req_recv_done
    req_forward
        req_forward_error (error forwarding)
            msg->error = 1
            msg->err = errno

req_filter
    req_response_to_client
            req_forward_error
                msg->error = 1
                msg->err = errno
req_forward
    req_response_to_client
            req_forward_error
                msg->error = 1
                msg->err = errno

{rsp_send_next,stats_rsp_send_next}
    req_error
        return msg->error msg->ferror
        如果ferror，则将分片的所有msg都标记为ferror=1

rsp_send_next
    if (req_error(req))
        rsp_make_error
            return msg_get_error(err or ferr) # 将errno转换为errstr


#### msg->done:

表示消息已经确定了回复，比如:收到的rsp，server_close回复errno、被swallow的rsp、
forward过程回复的errno（比如ETIMEOUT）、closing or migrating or need to close
时回复的-ERR closing, migrating, reloading消息、


server_close
    msg->done = 1 

rsp_recv_done
    rsp_forward
        pmsg->done = 1

rsp_recv_done
    rsp_filter
       if pmsg->swallow
           pmsg->done = 1 

req_forward_error: forward过程出现错误，都会直接回复errno到client
    msg->done = 1 

req_response_to_client: forward之前，拒绝forward并直接回复客户端
    msg->done = 1

client_close:
    if msg->done
        log & req_put(msg)

#### msg->swallow

表示收到rsp后不需要向client返回的消息，比如客户端已经放弃的消息，proxy发起的消息(info repl, auth, select, faketimeout)


client_close: 客户端close时，将所有没有完成的req标记为swallow 

server_send_info_repl: 发送info replication的消息被标记为swallow

req_forward:
    if (conn->need_auth)
        msg->add_auth(redis_add_auth_packet): auth命令被标记为swallow

req_send_next:
    if (conn->connecting)
        server_connected:
            conn->post_connect(redis_post_connect): select命令被标记为swallow

server_connect: 用于计算链接超时的消息标记为swallow

#### msg->noforward

表示不需要forward的消息，ping, quit, auth, auth_s, 所有auth之前客户端发送的命令

req_recv_done
    if (msg->noforward)
        if conn->authing, add msg to pipeq
        else 
            req_make_reply 
            msg->reply(redis_reply):对ping，auth，auth_s, ping, auth之前发送的命令，进行相应的回复
            event_add_out

#### msg->noreply

只对memcached有效，表示即使命令出错，server也不给客户端回复任何消息。


## fragment

需要fragment的命令包括del，mset，mget。

rsp_recv_done
    rsp_forward
        msg->pre_coalesce(redis_pre_coalesce)
            pr->frage_owner->nfrag_done++
            对于del，将rsp integer累加到frag_owner.integer
            对于mget，将mbuf移动到实际内容
            对于mset，直接将消息跳过(OK)

req_done: req_done是个神奇函数
    msg->post_coalesce(redis_post_coalesce)
        redis_post_coalesce_mget or ... : 拷贝frag的mbuf，然后回复
        redis_post_coalesce_mset or ... : 直接回复+OK
        redis_post_coalesce_del: 回复累加后的integer

req_recv_done
    msg->fragment(redis_fragment)
        redis_fragment_argx #根据分片规则，将submsgs分配好
    如果没有frag，则发送msg
    如果frag，则发送frag_msgq
            
## quit    

解析到quit命令，将msg->quit置为1；然后req_filter中将该消息丢弃；后续按照客户端断链处理

req_filter
   if (msg->quit)
       conn->eof = 1




## 读写分离

总体设计思路：

1. server添加stats_server[]，用于统计slave指标

2. 考虑slaves队列换成slave列表，这样的话slaves[]可以和stats_slave[]对应

3. info replication slaves变更
- 重建slaves[]，并且重新分配索引（因为stats_slave[]与其对应）
- 重建stat_pools,考虑stats_pool slaves数据继承问题

4. 动态生效
开启：确认能够初始化相应结构，并且添加相应stats结构；将负载分配到slave中
关闭：确认能够正常地清理slave，并且读取请求不在分配到slave；判断reload结束需要考虑到slave

5. 断链重连
- 与master处理类似，断链时直接close，丢失排队的所有msg；断链之后从alive_slaves中移除
- 重连则从重新添加到alive_slaves



测试问题
-------
1. redis_db: 1 会出现core
2. reload完成的判断是否同时需要判断slave状态
3. read_both, read_slaves策略修改
4. 选取slave之后，发现无法创建可用conn，那么应该尝试下一个slave。
5. 两个slave，kill client发现其中一个svr的client connection变成-1，不执行client kill 也变成了0
6. 在超时的情况下，发往slave的请求会hang住整个客户端；但是读写分离之前也是一样的会出现hang!!
7. 在新增或者减少slave时，会出现slave数据被清零


------

master deinit:

a. 初始化不成功，清理退出

b.
{core_worker_conf_regain, core_ctx_create不成功}
    server_pool_deinit
        server_pool_deinit_fn
            server_deinit

c.
server_pools_kick_state_machine
    server_pool_deinit_fn
        server_deinit
d.
server_pools_undo_partial_reload
    server_pool_deinit_fn
        server_deinit


综上： server_deinit出现在server_pool_create撤销，或者reload完成；
sever_deinit，需将server->slaves删除，同时reload完成的判断slave全部完成。


slave deinit:

slave_parse_info: 发现master下面的slave减少了之后，执行disconnect, deinit
    slave_disconnect
    slave_deinit


slave_deactivate: 删slave，slave dead期间

slave_activate: 增加slave，slave非dead期间

-----------------

reload 操作过程：

创建replacementpools，禁止stats swap；建立对应关系（该删掉pool直接删掉，新的pool把pconn转移过来直接可用；old draining
等待完成；

判断完成的过程fold（折叠）判断的过程。


config_reload_redis:
    server_pools_kick_replacement


--------------------
request标记

------------------
server->next_retry server断链之后，下次重试的时间。server_failure设置好下次重试时间，server_ok清除该时间。

server->next_rebuild

server->pname

server->name

server->weight


`set k v`最后怎么找到对应的svr发送出去？


------------------------
思考以下问题：

- 如果mset k1 v1 k2 v2 ... kn vn在frag之后，SVR[i]被隔离剔除，会不会造成该消息无法返回？
- 如果mset k1 v1 k2 v2 ... kn vn部分超时，会不会造成sub_msg内存泄露？
- 为什么从代码上看，每一个req都通过reqlog记录（时间，从那到哪...）？默认的日志级别到底是哪个？为什么链接日志被打印，但是其他日志没有被打印？


关于fragment的分析

req：

- MGET/DEL/MSET，按照步长1/2进行切片。
- 切片之后msg 进行fake reply，submsgs forward;

rsp：

- 先pre_coalese：整理好mbuf
- 再判断是否req_done
- post_coalesce: 将整理好的回复合并起来。

req_done的标准：

- 不需要fragment的被标记为done
- 需要fragment的：a. 已经被标记为fdone b. 跟当前submsg在一条线上的所有submsg已经被标记为done

什么情况submsg会被标记为done:收到rsp就是done
什么时候submsg会被free掉，并且不会被发送到客户端链接中:





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



# 关于ttl功能

由于redis中有控制每一个key的ttl的需求，而rocksdb没有提供该功能，并且该部分功能
属于数据结构中的公共部分，因此参考nemo-rocksdb在rocksdb之上，添加ttl功能。

涉及需求：
- 提供db->put(options, k, v, ttl)接口
- compactionr-filter自动过滤过期kv
- iterator自动跳过过期kv

## redis ttl相关命令

[key]
expire key seconds
expire at key timestamp
pexpire key milliseconds
pexpire at key milliseconds-timpstamp
persist key
ttl key
pttl key

[stirng]
set key value [EX seconds] [PX milliseconds] [NX|XX]
setex key seconds value

## 相关工作

相关的工作包括rocksdb的DBWithTTL类和nemo-rocksdb的DBNemo类。

### rocksdb DBWithTTL

rocksdb提供了DBWithTTL，该类Open时传入ttl参数，也就是所有的key共享一个ttl。
明显地，该类的功能不能满足redis ttl的需求；

虽然不满足需求，DBWithTTL提供关于ttl功能的一个比较完备的设计与实现示例，对于
实现ttl功能涉及的compaction-filter、merge、iterator有比较重要的指导作用，
可以看出nemo-rocksdb也是参考了DBWithTTL类进行了定制开发。

### nemo-rocksdb DBNemo

DBNemo实现了kv级别ttl功能，主要的设计思路是：将每个kv（无论是否有ttl属性）都
append (version, timestamp)。其中version用于推迟删除到compaction（删除
list/hash时version++，如果list/hash的节点version小于当前version则说明list/hash
被删除）。

虽然DBNemo实现了kv级别ttl，但其设计与nemo数据 结构设计紧耦合，限制了我们使用
其ttl功能重新设计。


综上：以上两种实现都不能很好地满足redis持久化需要用到的kv级别ttl功能。

## 总体设计

### 存储结构

示意图如下：

```
------------------------------------------
redis层

    +-----+   +-------+
    | key |   | value |
    +-----+   +-------+

------------------------------------------
db-keyttl层

    +-----+   +---------------------------+
    | key |   | value| [timestamp] | flag |
    +-----+   +---------------------------+

-------------------------------------------
rocksdb层

    +-----------+     +-----------+
    |           |     |           |
    |    ....   |     |    ....   |
    | memtables | ... | memtables |
    |    ....   |     |    ....   |
    |           |     |           |
    +-----------+     +-----------+

    +------+    +------+         +------+
    |      |    |      |         |      |
    | .... |    | .... |         | .... |
    | SSTs |    | SST  |  ...    | SST  |
    | .... |    | .... |         | .... |
    |      |    |      |         |      |
    +------+    +------+         +------+

--------------------------------------------
```

DBWithKeyTtl层：

类似于协议栈，DBWithKeyTtl层在value之后添加了timestamp和flag两个域。

- flag      : 附属标志（目前只用于标记是否有timestamp域）
- timestamp : 超时timestamp，可选域（如果没有timestamp，表示不超时）

### 项目组织

DBWithKeyTtl层的实现的备选方案：
- c++方案: c++编写，独立项目（与nemo-rocksdb类似）
-   c方案：c编写，redis子模块

#### c++方案

参考nemo-rocksdb，使用c++编写，单独创建项目db-keyttl。使用c++的多态特性，
override rocksdb::StackableDB中的相关接口，定制ttl功能。

优点：
- 可参考nemo-rocksdb
- 可以使用c++的面向对象特性进行设计
- 独立项目，rocksdb可以单独升级

缺点：
- c++语言特性不熟悉
- 需要参考rocksdb将db-keyttl的类bind为c语言接口


#### c方案

使用c编写，作为子模块放在redis源码项目中。使用c语言的函数指针override相关的
virtual函数，定制ttl功能。

优点：
- c语言特性少，更熟悉
- 不必再独立维护一个项目

缺点：
- 暂时没有看到相关的参考，poc耗时稍久
- 将c++的特性对应到c实现，可能会有不方便的地方


## 详细设计

超时功能虽小，但是涉及到了compation-filter、merge-operator、iterator等相关
功能，以下逐一分解。

### compaction-filter

kv超时之后，需要compation时自动过滤，从而降低磁盘占用。

rocksdb为了实现用户自定义过滤策略，定义了compactionFilter接口类：

```
class CompactionFilter {
  ...
  virtual bool Filter(int level, const Slice& key, const Slice& old_val,
                      std::string* new_val, bool* value_changed) const;
  ...
}
```
KeyTtlCompactionFilter继承CompactionFilter并override Filter函数可以自定义过滤
策略，Filter函数：
- 返回true，表示该key需要丢弃
- 放回false，表示该key应该保留

rocksdb通过ColumnFamilyOptions/Options持有CompactionFilter实例，从而持有
自定义的KeyTtlCompactionFilter，执行ttl相关的过滤策略。

另外为了支持用户自定义Filter策略，KeyTtlCompactionFilter应该先执行用户通过
options传入的user compaction filter，然后再执行ttl相关的Filter策略。

### iterator

迭代器在以下场景可能遇到过期kv：
- iterator创建时kv已过期但尚未执行compaction
- iterator迭代过程长，迭代过程中有些kv过期

因此需要在迭代的过程中检查kv是否过期，并且自动跳过过期kv。


```
class Iterator {
    virtual bool Valid() const = 0;
    virtual void SeekToFirst() = 0;
    virtual void SeekToLast() = 0;
    ...
}

```

KeyTtlIterator通过继承Iterator并override Valid/SeekToFirst/SeekToLast等函数
自动跳过过期kv。db-keyttl通过继承StackableDB并override NewIterator来创建
KeyTtlIterator实例，从而使得db持有Iterator。


### merge-operator

merge是rocksdb抽象出来的一种read-modify-write的操作。merge与put，get，delete
一样是rocksdb支持的基本的操作类型。

merge操作类似于update操作，特殊的是merge的update操作可以通过继承MergeOperator
并override FullMergeV2来自定义merge操作。

如果把merge operator表示为'*'， kv表示为'(k,v)'，merge结果表示为(k,v_new)，则
(kv)连续与m1,m2,m3 merge过程可以表示为：
```
(k,v_new) = (k,v)*m1*m2*m3
```
因此如果merge操作满足结合律(associativity)，那么可以通过PartialMerge进行优化，
更加详细的资料参考：
- [merge operator](https://github.com/facebook/rocksdb/wiki/Merge-Operator)
- [merge operator implementation](https://github.com/facebook/rocksdb/wiki/Merge-Operator-Implementation)

----------------------------

由于merge是rocksdb支持的基本操作，毋庸置疑merge操作需要得到支持；由于ttl层对
用户透明，因此KeyTtlMergeOperator需要完成redis层到rocksdb层的中转。具体包括：
- 用户merge操作的operands应该Strip掉timestamp和flag 
- 用户merge的超时时间与existing_value一致



-------------------------- 华丽的分割线 --------------------------

TODO

- review
    - ttl的精度问题
    x 关于env的设计逻辑是什么？为什么要把env传来传去？
    x- 整理static函数
    x WriteWithOldKeyTtl
    x 为什么string和slice混合使用？



- test
- performance







