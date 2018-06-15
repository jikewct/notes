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







