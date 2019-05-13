#format markdown

# 关于rocksdb的分享

## 总体框架

![rocksdb](rocksdb.png)


### 模块组织

```
| --- | ---------------          | -----------------                                     |
| WAL | Write Ahead Log          | 数据库日志，类似于redolog                                      |
| SST | ??                       | leveldb的数据存储文件，文件中的kv默认按字典序排列              |
| mm  | memtable(writebuffer)    | 内存表，默认实现为skiplist                                     |
| imm | immutable memtable       | 不可变内存表，通常mm满了之后转换为imm                          |
| cf  | column family            | 列簇，类似于数据库表；包含一个                                 |
| sv  | super version            | cf的一个consistent视图。包含memtable和SSTs                     |
| sn  | sequence number,snapshot | 数据版本号，snapshot表示也是版本号                             |
| ve  | version edit             | 数据库变更记录，包括: New file, Delete file, Comparator edit等 |
| Vs  | Version Set              | 数据所有活动Version                                            |
```

### 文件组织

```
| --------      |      ------------                                          |
| IDENTITY      | 复制使用的uniq id                                          |
| LOCK          | 锁文件，rocksdb db只能由一个进程打开（可以有多个readonly） |
| archive/*     | archive的log                                               |
| SST           | 数据存储文件                                               |
| xxxx.log      | WAL文件                                                    |
| LOG           | 调试日志                                                   |
| OPTIONS-yyyy  | 配置文件                                                   |
| CURRENT       | 指向当前MANIFEST                                           |
| MANIFEST-zzzz | MANIFEST文件，数据库版本变更日志文件                       |
```

### 操作


```
| ------        | ------------------------------------------------------------          |
| switch        | Memtable和WAL切换;切换时WAL切换新文件和mm-->imm;WAL或者mm full时触发switch操作。          |
| flush         | 将imm写入到sst文件；超过max_write_buffer_number将触发flush操作；flush操作由threadpool执行 |
| minor compact | level0-->level1（与major compact不同的是level0文件key范围可重叠)                          |
| major compact | levelN-->levelN+1，N>=1                                                                   |

```

## write分析

基本思路是：采用single write模式，从多个DB::Write选线程取leader，
执行写WAL, memtable操作；其他线程作为follower等待leader执行完成。

值得注意的是对于skiplist这种支持cocurrent insert的数据结构，rockdb
将并发写memtable加速写过程。

![rocksdb-writegroup](rocksdb-writegroup.png)


```

WriteImpl:
  JoinBatchGroup

  //并发写memtable，完成本线程写memtable任务
  if role == PRARLLEL_MEMTABLE_WRITER
    InserInto  //将writebatch写入memtable
    if CompleteParallelMemTableWriter //等待所有并发写memtable的writer完成，最后一个完成的执行ExitAsxxxx
       //收尾工作
       ExitAsBatchGroupLeader
       更新versions_.last_sequence
    return w.FinalStatus();
  
  //被选为leader，完成WAL和memtable写入
  assert role == LEADER //只有leader做parpare和writeToWAL操作
  
  PreprocessWrite   //write前准备
    HandleWALFull
    HandleWritebufferFull
    DelayWrite      //控制write速率
 
  EnterAsBatchGroupLeader   //生成WriteGroup

  WriteToWAL    //写WAL，options.sync可以选择是否sync

  判断是否allow_concurrent_memtable_write 

  if !allow_concurrent_memtable_write
    leader InsertInto memtable
  else 
    LaunchParallelMemTableWriters
  
  MarkLogsSynced //清除DB::logs_中的非current logs_ （但文件不会被清除）

  if CompleteParallelMemTableWriter //等待所有并发写memtable完成，最后一个完成的执行ExitAsxxxx
    //收尾工作
    更新versions_.last_sequence
    唤醒下一个leader(ExitAsBatchGroupLeader)

```

其他：

- rocksdb支持跨cf的原子写

- write stall
  当compaction和flush无法跟上incoming write速度，rocksdb将限制write速度。以免
  系统出现：空间放大，读放大。

- pipelined write

## read分析


```
GetImpl
  sv = GetAndRefSuperVersion //获取当前sv，引用计数++
  获取snapshot  //最新的sn或者read_option中指定的sn

  sv->mem->Get(k,v)
    bloom_filter_ 过滤
    table_->Get(k)
  sv->imm->Get(k,v)     //遍历imm列表中的每个列表，直到找到k
  sv->current->Get(k,v) //current是当前的version
     table_cache_->Get(k)   //table_cache中查找到文件，然后再定位到具体值

  ReturnAndCleanupSuperVersion  //sv引用计数--
  
```

## merge分析

- merge operator通过Options传入（也就是open时传入）

- get算法


```
K:   OP1    OP2   OP3   ....    OPk  .... OPn
            Put  Merge  Merge  Merge
                                ^
                                |
                              Get.seq
            -------------------->
```

从Get.seq 按照newest-->oldest顺序，找到第一个非merge操作（put/del)，然后执行
merge操作，计算merge之后的结果。

如果 merge operator满足结合律（override了PartialMerge）则可以通过PartialMerge
一边向左（-->oldest）搜索(第一个非merge操作），一边PartialMerge。

- compaction算法


```
K:   OP1     OP2     OP3     OP4     OP5  ... OPn
              ^               ^                ^
              |               |                |
           snapshot1       snapshot2       snapshot3

```
如果没有merge操作，compaction留下OP2, OP4, OPn。


```
K:    0    +1    +2    +3    +4     +5      2     +1     +2
                 ^           ^                            ^
                 |           |                            |
              snapshot1   snapshot2                   snapshot3

```

merge算法：
向左（-->oldest）搜索，找到第一个supporting操作（put/del)，执行合并
- 如果找到put/del则merge
- 如果找到snapshot，则停止

因此上述案例compaction结果为：


```
K:               3           +7                           5
                 ^           ^                            ^
                 |           |                            |
              snapshot1   snapshot2                   snapshot3
```


参考[Merge-Operator-Implementation](https://github.com/facebook/rocksdb/wiki/Merge-Operator-Implementation)


## iterator分析

- iterator可用于迭代一个column family的kv列表
- cf含有mem，imms，SSTs
- mem,imm,SSTs都是有序的，但是mem,imms,SSTs(level 0)的key范围有重复
- iterator必须结合mem，immm，SSTs才能迭代整个column family

为了实现iterator迭代，rocksdb设计了按照下图组织了iterators：

![rocksdb-iterator](rocksdb-iterator.png)


- superversion保存了当前迭代的mem, imems, SSTs列表；
- column family的每个组件各自实现iterator:MemtableIterator, TwolevelIterator；
- MergingIterator将各组件的iterator组合起来（各组件的iterator成为child iterator)

MergingIterator使用min heap保存所有组件的iterator，迭代算法如下：
Seek: 所有child iterator都执行seek，然后重建minheap
Next: 取出当前minheap top（就是返回值），然后top.Next()，再把top重新添加到minheap




## TODO

## options

## MVCC

## 事务模型

## 数据库恢复

## 线程模型

## 并发控制

## 统计信息

## 无锁编程

## compaction filter

```
options.compaction_filter
options.compaction_filter_factory
```

如果只有一个compact filter，则这个filter必须线程安全（compaction会并发运行）。
如果提供了cff，那么每个compaction job都会提供从cff中创建一个cf。这样的话cff
必须是线程安全的。

cf有两套api：

1)Filter/FilterMergeOperand     提供是否需要过滤的callback
2)FilterV2                      提供了修改结果的可能性

## merge operator


```
options.merge_operator
```


## 主主复制支持

PutLogData可以给每个Put操作添加timestamp和serverid等元信息，可用于检测复制循环
该信息只存储在wal中。

## github wiki

### 描述

- RocksJava是一个rocksdb的java版本driver
- 拥有很多配置项，可以适用于mem，Flash，硬盘，HDFS等

### 特性

- TB级存储
- 对于中小key-value在内存和flash上的存储进行优化
- 多线程，能利用多核能力

### 历史

干货满满：http://rocksdb.blogspot.ca/2013/11/the-history-of-rocksdb.html

- 作者原来做hdfs的（到2011年已经做了五年）
- 来自作者的数据：硬盘rw-10ms，ssd 0.1ms，network延迟0.05ms：说明数据库应该存在本地（嵌入式），而不是存储在数据中心
- 嵌入式db目前已有：berkerlydb， kyotodb，sqllite， leveldb
- ssd的写寿命有限，并且会引入大量的写放大
- leveldb的mmap引发读性能不好？
- leveldb无法充分利用ssd的特性
- 作者看好flash存储的发展，并且为该类存储定义了WAF，RAF,SAF

所以，rocksdb的一些设计初衷：

1. An embedded key-value store with point lookups and range scans
2. Optimized for fast storage, e.g. Flash and RAM
3. Server Side database with full production support
4. Scale linearly with number of CPU cores and with storage IOPs
5. 作者在大约2013年底的时候完成了主要功能

RocksDB is not a distributed database. It does not have fault-tolerance or replication built into it. It does not know anything about data-sharding. It is upto the application that is using RocksDB to implement replication, fault-tolerance and sharding if needed.

### overview

- 支持get，put，delete, scan
- memtable, sstfile, logfile为rocksdb的三种基本结构
- Multiget是数据一致的
- iterator的数据也是一致的
- snapshot不会持久化
- 支持key-prefix scan（利用bf做过优化）
- 使用了batch-commit来优化写
- 支持校验，并自动检测硬件校验
- 多线程compact能够提升高达10x性能（普通SATA盘是没有这个优势的，说的是SSD）
- 有两种compat：Universal，Level
- compaction支持过滤（可用于expire）
- 支持只读模式（可用于读写分离吧）
- 拥有调试日志
- 支持多种压缩
- 支持交易日志，并且可以把交易日志放到另外的文件夹（这样的话，可以把整个sst文件放到volatile的存储中）
- 由于lsm算法中的文件只有创建，没有修改；因此可以很方便进行全量复制
- putlogdata支持添加data元数据
- 所有的交易日志是会被放到archive文件夹中的，因为复制可能崩掉
- 单进程可以操作多个database，通过Env共享compact线程池，共享blockcache
- blockcache分为未压缩和压缩的blockcache
- tablecache sst的文件描述信息cache
- 支持外部的压缩算法

- 有两种compat：Universal，Level
- compaction支持过滤（可用于expire）
- 支持只读模式（可用于读写分离吧）
- 拥有调试日志
- 支持多种压缩
- 支持交易日志，并且可以把交易日志放到另外的文件夹（这样的话，可以把整个sst文件放到volatile的存储中）
- stackabledb 是db kernel之上的一层东西（实现了backup，ttl）

- memtable可以替换（对于不需要有序性场景非常有用），自带了skiplist, vector, prefix-hash三种memtable
- 支持三种record：put，del，merge

- 工具包括：sst_dump，ldb
- db_stress用于压测
- db_bench可用于性能测试

### basic operations

- Put, Delete, Get, Merge
- WriteBatch Write
- DB, put, get, getIt线程安全，但是writebatch以及iterate非线程安全


代码研读
---

- 基础结构：主要的类，以及类uml关系，文件组成，组件组成

* table
- plain和sst，通过option选择，默认sst；
- sst

[data block 1]
[data block 2]
[data block ...]
[meta block 1 filter block]
[meta block 2 stats block]
[meta block ...]
[meta index block]
[index block]
[footer]

* MANIFEST

```
MANIFEST = { CURRENT, MANIFEST-<seq-no>* } 
CURRENT = File pointer to the latest manifest log
MANIFEST-<seq no> = Contains snapshot of RocksDB state and subsequent modifications
```
文件的多版本体系。

* compaction
- 类型包括：universal,level,fifo, 默认level?
- L0,L1,L2 target（容量）指数增长；L0可以overlap，L1,L2...不可以overlap
- L0的文件数量超过 level0_file_num_compaction_trigger；L1..Ln的容量超过target会触发compaction
- L1->L2, L2->L3, ...最多可以max_background_compactions个并发合并；L0->L1 max_subcompactions控制并发
- compaction先选level，再选文件
- compaction的target策略有两种：level_compaction_dynamic_level_bytes 
false:固定的 target比例
true：分别是90%, 9%，0.9%

* memtable(aka write_buffer)
- memtable满了之后，变成immutable memtable
- memtable在达到write_buffer_size, 超过db_write_buffer_size, WAL超过max_total_wal_size之后可以

* prefix seek
- 当prefix_exactor不为null时，iterator不保证所有的迭代元素都是有序的
- 用来优化 prefix bloom

* single delete
- 直接删除该key的最后一个版本，但是之前的版本是否会诈尸是undefined
- 前提是该key存在并且没有被覆盖，是特殊场景用来优化性能的特殊操作，experimental

* TTL
TTL只能在open时指定

* WAL
- 格式也是和sst类似那种三段式的分布，非文本的格式
- reader/write/manager提供了顺序读取的基础脚手架
- 一致性和完整性？
- WAL四种恢复模式的比较有利于理解数据库的困境

* EventListener

- 给出了一系列的hook，可以用于外部统计和插入式compaction算法

* Rate Limiter
- 算法可以用于参考

* 事务
- 与redis不同，rocksdb提供了比较完备的事务支持，包括乐观事务和悲观事务
- begin/commit/rollback比较熟悉的事务原语
- 乐观事务与悲观事务的区别是事务在进行准备的阶段是否获取锁！

writebatch提供了原子特性，事务则保证了batch只有在不造成冲突的情况才会提交，其他线程
看不到transaction中的变化。

在transactiondb中所有被写的key都会被rocksdb内部锁定，如果当前key不能被锁定，则当前操作
出错，事务只要提交，那么该事物一定能成功（如果db可写）。

lock超时时间和限制可以在TransactionDBOptions中调整。

write policy默认是write commited，（可选的有write prepared，write unprepared）

OptimisticTransactionDB
乐观db则不锁定，只是在提交的时候检查冲突，如果有冲突则提交失败。

在事务中可以设置snapshot，用来获得一致的读体验。


------------------------
- write policy ? why ? what? 
- why set up snapshot in trans? 难道是repeatable read？

- 关于基本操作的理解put,get,del,merge,single delete, write batch, multiget, iterator, snapshot, compact, flush
- 关于compaction的理解：compaction style，compaction filter
- 关于snapshot，复制的理解
- 关于事务的理解

------------------------------
write policy:
- 默认是WriteCommited：只有在事务提交之后才会讲数据写入到memtable，因此读取到的数据可以认为是已经commit之后的
- WriteCommit简化了read操作，但是由于事务提交冗长，会限制数据库吞吐量

两阶段提交：
- write stage ：  调用了 put
- prepare phase ： 调用了 prepare
- commit phase: 调用commit，数据对其他事务可见

memtable write可以在put或者prepare phase，

感觉应该看点二手资料！
关于经典的2pc：
- 两个角色：coordinator&paticipant
- （投票）prepare阶段：client向co提交请求，co向pa发送应该prepare成功（说明后续一定能够commit成功）
- （执行）commit阶段：co持久化本地事务，向pa发送commit命令；pa收到命令之后，本地commit，向co应答；co向客户端应答

局限：
- co宕机之后，pa全部阻塞
- 提交逻辑较长，延迟高


费了这么多的设计，benchmark结果显示提高性能%3，%7，而且牺牲了隔离级别，真的很不值。

-------------------
关于rocksdb使用的一些c++高级特性的理解：

- using的原因：因为c++的继承与java不同，使用java的类可以直接访问Base的继承函数
但是c++不行，c++需要显示指明哪个基类！使用using就可以比较优雅地解决该问题。


- 继承并且持有的原因：因为喜欢？咱不纠结！

- ClassImpl的设计逻辑： Class的接口尽量简单，Impl中override必要的函数；
最重要的是：Impl override的Open函数，new出来的是Impl的实例，因此才能应用重写的函数。


# rocksdb阅读

## c bindings

- Static函数绑定最直接，成员函数绑定第一个参数为Object，override通过函数指针，overload通过不同函数名

暴露出的概念：db, backup_engine, checkpoint, column family, iterator, snapshot, compact
              writebatch, writebatch_index,  block_based_option, cucoo, options, bulkload,
              ratelimiter, comparator, filterpolicy, MergeOperator, sync/flush, cache, env
              sst, slicetransform, universal/fifo/level compaction, transaction



## 基本概念

### options

Options
ColumnFamilyOptions
DBOptions
ReadOptions
WriteOptions

### column family

每个操作都有操作的cf，默认为default cf。

ColumnFamilyDescriptor //静态描述
ColumnFamilyHandle  //动态句柄

CreateColumnFamily  // 通过cfd，创建cf（得到cfh）
DropColumnFamily    //（通过cfh）删除cf
Open  //通过cfd list打开为cfh list



# 问题

## rocksdb的磁盘满问题

https://github.com/facebook/rocksdb/issues/919

上游的意思是直接restart db。

ardb 目前直接放弃治疗

cockrochdb的方法是在rocksdb报错前报错，防止进入rocksdb的磁盘满状态。

目前upredis-rks选择ardb一样的做法，放弃治疗，直接重启解决问题。

## rocksdb tliter 


PurgeObsoleteFiles
    DeleteFile   
    DeleteFilesInRange
    CleanupIteratorState
    EnableFileDeletions

FindObsoleteFiles

sst是否obselete由versionset说了算。

所以说最终是versionset说了算


所以说，这个问题是rocksdb本身的问题：

- rocksdb的versionedit把a sst加入到obselete列表
- compaction 又把a sst拿出来再做一次compact，这不是脑裂了吗?

## 性能监控

- PerfContext提供per-thread维度的性能监控统计, perf_level控制perf是否统计时间相关信息
- Statistics提供per-db维度的性能监控统计，需要通过options开启statistics统计

- DB properties report current state of the database
- DB statistics give an aggregated view across all operations
- perf and IO stats context allow us to look inside of individual operations.

### PerfContext

PerfContext，线程私有变量，保存各操作线程的性能统计数据。

通过perf_level控制metric的精细程度，默认不统计TIMER信息。

PerfContext包含两类metric：

- COUNTER : 通过`PERF_COUNTER_ADD`宏操作，执行metric累加
- TIMER : 通过`PERF_TIMER_*`操作，执行metric时间(ns)累加

由于是线程私有变量，因此只能获取本线程的统计量。

### Statistics

Statistics，per-db性能统计（线程安全）。

options.statistics控制是否开启，通过stats_level控制级别：

- kExceptDetailedTimers: 压缩时间不统计、上锁之后不统计
- kExceptTimeForMutex: 上锁之后不统计
- kAll: 统计所有时间

包含两类数据：

- Tickers : RecordTick累加
- Histograms :MeasureTime增加样本

在实现上，StatisticsImpl采用了per-cpu结构分别存储各cpu上的统计信息，降低并发；
获取结果时，加锁聚合各cpu结果。

### DB Property

获取当前运行的db的属性。

每个cfd对应一个internal_stats，cf相关的统计信息可以直接合并到internal_stats_。

compaction后且间隔超过options.stats_dump_period_sec，rocksdb将打印stats。

实现要点：

- 通过GetProperty roccksdb.xxx 接口获取相应的property
- cfd与internal_stats一一对应
- 每一个property有两个要素：名称、获取方法
- 获取方法的抽象限制小，灵活可变，每个property一种方法
- property的数据源包括 VersionStorageInfo, VersionEdit, cfd等

注意点：

db_stats_与stats_有一部分指标重合，这是因为stats_可能并没有开启，但是有些统计
指标不论是否开启都应该记录；另一方面，stats_可能是跨越多个db的（比如pika）
统计数据，但是dbstats则只针对本db，因此统计的角度不同，不能共用数据，因此分别
统计。

default_cf_internal_stats_保存了rocksdb.dbstats，这是因为dbstats中的指标与cf
无关，因此放在默认internal_stats中。

internal stats目前包括以下属性:

```
int:
    "rocksdb.num-immutable-mem-table"
    "rocksdb.mem-table-flush-pending"
    "rocksdb.compaction-pending"
    "rocksdb.background-errors"
    "rocksdb.cur-size-active-mem-table"
    "rocksdb.cur-size-all-mem-tables"
    "rocksdb.size-all-mem-tables"
    "rocksdb.num-entries-active-mem-table"
    "rocksdb.num-entries-imm-mem-tables"
    "rocksdb.num-deletes-active-mem-table"
    "rocksdb.num-deletes-imm-mem-tables"
    "rocksdb.estimate-num-keys"
    "rocksdb.estimate-table-readers-mem"
    "rocksdb.is-file-deletions-enabled"
    "rocksdb.num-snapshots"
    "rocksdb.oldest-snapshot-time"
    "rocksdb.num-live-versions"
    "rocksdb.current-super-version-number"
    "rocksdb.estimate-live-data-size"
    "rocksdb.min-log-number-to-keep"
    "rocksdb.total-sst-files-size"
    "rocksdb.base-level"
    "rocksdb.estimate-pending-compaction-bytes"
    "rocksdb.num-running-compactions"
    "rocksdb.num-running-flushes"
    "rocksdb.actual-delayed-write-rate"
    "rocksdb.is-write-stopped"
    "rocksdb.estimate-oldest-key-time"

string:
    "rocksdb.num-files-at-level<N>"
    "rocksdb.compression-ration-at-level<N>"
    "rocksdb.stats"
    "rocksdb.sstables"
    "rocksdb.cfstats"
    "rocksdb.cfstats-no-file-histogram"
    "rocksdb.cf-file-histogram"
    "rocksdb.dbstats"
    "rocksdb.levelstats"

API:

rocksdb_property_value  //int或者stirng
rocksdb_property_value_cf //int或者string
rocksdb_property_int //int

GetProperty //可以获取int或者string property
GetIntProperty  //只获取int propterty
GetAggregatedIntProperty // 获取cfs聚合结果
GetMapProperty  //获取map结果

DS：

InternalStats {

    //保存了property和获取方法列表
    ppt_name_to_info : { string => DBPropertyInfo { 
        need_out_of_mutex
        handle_string
        handle_int
        handle_map
    }}

    // compaction stats
    static compaction_level_stats;

    //per-db stats
    db_stats_ : [int64_t]

    //per-cf stats
    cf_stats_value_ : [int64_t]
    cf_stats_count_ : [int64_t] 

    //per-cf level compaction stats
    comp_stats_    
    file_read_latency_
    
    // used to compute per interval stats
    cf_stats_snapshot_
    db_stats_snapshot_
    bg_error_count_

    // misc
    number_levels_
    env_
    cfd_
    started_at_

}

class DBImple {
    ...
    default_cf_internal_stats_
    ...
}

```

## rate limit

```
API:

GetDelay


DS:

GenericRateLimiter {
    request_mutex_
    max_bytes_per_sec_
    rate_bytes_per_sec_
    refill_period_us_
    refill_bytes_per_period_
    next_refill_us_
    fairness_
    rnd_
    total_requests_
    total_bytes_through_
    env_
    exit_cv_
    requests_to_wait_
    available_bytes_
    num_drains_
    prev_num_drains_
    leader_
    auto_tuned_
    tuned_time_
} + RateLmiter {
    mode_
}

WriteController {

    total_requests_
    total_stopped_;
    total_delayed_;
    total_compaction_pressure_;
    bytes_left_;
    last_refill_time_;

    max_delayed_write_rate_;

    delayed_write_rate_;

    low_pri_rate_limiter_;
}

```

## write_controller

```
ColumnFamily {
    write_controller_token_
    ...
}
```

控制整个db写入的调度策略。

RecalculateWriteStallConditions
    InstallSuperVersion
        InstallSuperVersionAndScheduleWork //同时schedule flush和compaction
            |SetOptions
            |CreateColumnFamilyImpl
            |DeleteFile
            |DeleteFilesInRange
            |IngestExternalFile
            |SwitchMemtable
            |Open
            |FlushMemTableToOutputFile
            |CompactFilesImpl
            |ReFitLevel
            |BackgroundCompaction

- 如果num_not_flushed > max_write_buffer_number则stop，会打印warn级别stop日志
- 如果l0文件数量超过level0_stop_writes_trigger则stop, 会打印warn级别stop日志
- 如果compaction_needed_bytes>hard_pending_compaction_bytes_limit则stop，会打印warn级别stop日志

- 如果max_write_buffer_number > 3且num_not_flushed>=max_write_buffer_number-1则delay，并打印warn级别stall日志
- 如果l0文件数量超过l0_delay_trigger_count，则delay?
- 如果compaction_needed_bytes>soft_pending_compaction_bytes_limit，则delay

- 如果l0_delay_trigger_count > GetL0ThresholdSpeedupCompaction，则增加compaction线程
- 如果estimated_compaction_needed_bytes > soft_pending_compaction_bytes_limit/4，增加compaction线程

- 如果之前已经在delay状态，则重新计算delay_write_rate = 1.4*delay_write_rate


Flush操作(高IO优先级):

max_flushes


Compaction操作(低IO优先级)：

max_compactions


## 日志打印

INFO LOG:

默认INFO级别，不打印级别。

INFO LOG通过调用宏打印对应级别的日志，少部分通过Header打印不含时间戳的信息。

EventLogger:

EventLogger打印json格式日志。

设计思路类似于iostream，提供了一些json格式化的运算符和函数。

写eventlog分两步：格式化+flush。格式化默认采用jsonwriter，格式化
成一个json string，写入使用传入的info_log。


## 压缩

支持SNAPPY, ZLIB, BZIP2, LZ4, ZSTD, XPRESS 6中压缩算法。

内存中不压缩，创建sst时压缩。

## column family

```
CFD {

  id_
  name_
  dummy_versions_
  current_
  next_
  prev_
  refs_
  initialized_
  dropped_

  initial_cf_options_
  ioptions_
  mutable_cf_options_
  internal_comparator_
  int_tbl_prop_collector_factories_
  is_delete_range_supported_
  allow_2pc_

  mem_
  imm_
  super_version_
  super_version_number_
  local_sv_
  log_number_
  column_family_set_

  table_cache_
  internal_stats_
  write_buffer_manager_
  compaction_picker_
  write_controller_token_
  pending_flush_
  pending_compaction_
  prev_compaction_needed_bytes_
}

SuperVersion {
    mutable_cf_options
    version_number
    db_mutex
    refs

    write_stall_condition
    to_delete

    mem
    imm
    current // Version
}

```

sv就是v+mm。

version,sv,wal,sst,mm与cfd的关系：

- 如果version只包含sst，并且只有完成compaction、flush之后才会生成version
  由于wal并不是version考虑的范畴，那么重启之后，怎么继续做未完成的flush操作？
- sv包括mm和sst，sv信息没有固化，那么重启之后无法恢复sv?
- 为什么cfd包含v列表，但是只包含单个sv？
- sv直接包含v？


## version

```
Version {
  version_number_  
  env_options_

  cfd_
  db_statistics_
  info_log_
  table_cache_
  merge_operator_

  next_
  prev_
  refs_

  vset_

  storage_info_ : VersionStorageInfo {
      ...
      files_
      ...
  }
}

VersionSet {
  dbname_
  env_
  env_options_
  env_options_compactions_
  const db_options_

  next_file_number_
  manifest_file_number_
  options_file_number_
  pending_manifest_file_number_

  prev_log_number_
  descriptor_log_
  current_version_number_

  manifest_writers_ //leader, follower manifest writer queue
  manifest_file_size_

  last_sequence_
  last_to_be_written_sequence_

  obsolete_files_
  obsolete_manifests_
}

```

## manifest

```
Class VersionEdit {
  max_level_

  comparator_
  has_comparator_

  has_log_number_
  log_number_

  has_prev_log_number_
  prev_log_number_

  has_next_file_number_
  next_file_number_

  has_last_sequence_
  last_sequence_

  has_max_column_family_
  max_column_family_

  column_family_
  is_column_family_drop_
  is_column_family_add_
  column_family_name_

  deleted_files_
  new_files_ : {filenumber => FileMetaData}
}

```

VersionEdit类型：

```
Tag {
  kComparator = 1,
  kLogNumber = 2,
  kNextFileNumber = 3,
  kLastSequence = 4,
  kCompactPointer = 5,
  kDeletedFile = 6,
  kNewFile = 7,
  // 8 was used for large value refs
  kPrevLogNumber = 9,

  // these are new formats divergent from open source leveldb
  kNewFile2 = 100,
  kNewFile3 = 102,
  kNewFile4 = 103,      // 4th (the latest) format version of adding files
  kColumnFamily = 200,  // specify column family for version edit
  kColumnFamilyAdd = 201,
  kColumnFamilyDrop = 202,
  kMaxColumnFamily = 203,
}
```

vs保存了当前version的全局信息，提供了一些全局方法，并不是version的集合。

分析以下三种操作下v，ve，sv，cfd的变动：

- switch
- flush
- compaction


### LogAndApply

- rocksdb写文件都是一个尿性，分leader和follower角色，leader干活follower干等，
- 一个version可能包含了多个versionedit(只要没有跨越columnfamily)。
- builder把versionedit*保存到v->vsi
- filenumber全局共享，单调递增NewFileNumber?
- descriptor log就是他喵的manifest 
- install new version 会把version放入到cfd的version链表中

如果新创建一个manifest文件，怎么把前面的manifest文件合并起来？

通过WriteSnapshot重新开始，一个SnapShot包含两个VE：

- cfd info: id,name,comparator
- cfd files: [level,number,pathid,size,smallest,largest,smallest_seqno,largest_seqno,marked_for_compaction]

另外会新建一个current文件，指向当前的manifest文件

如果manifest更新失败了怎么办？
如果manifest日志写入耗费了很长时间怎么办？

有没有可能因为version增加的太快导致hang？
version增加有没有并发，多cfversion变更？
为什么需要维护一个version队列？

### InstallSuperVersionAndScheduleWork

### SwitchMemtable


```
WriteContext {
    superversion_context : SuperVersionContext {
        write_stall_notifications : WriteStallNotification {
            write_stall_info : WriteStallInfo
            immutable_cf_options
        }
        superversions_to_free : [SuperVersion]
        new_superversion
    }
    memtables_to_free_: [MemTable]
}
```

- new memtable
- new logfile, sync old logfile, add to logs_
- install new mem to cfd
- install superversion(附带更新write stall)

SwitchMemtable
    |SwitchWAL
        PreprocessWrite //只有在wal大小大于max_total_wal_size才会强切wal，通常都是因为memtable切换造成的切换WAL
    |HandleWriteBufferFull
    |ScheduleFlushes

### leveled compaction

问题：

- L0->L1是以L0为参照pick(读写放大有点夸张), 还是以L1为参照pick（我会选这个)
- LN->LN+1是以LN为参照，还是以LN+1为参照（我选LN+1)
- 什么情况下需要新建LN+1?
- Compaction过程会不会产生碎片式sst？如果产生，那么需要 LN->LN的compaction?
- 怎么保证最后形成的LSM tree不倾斜，是金字塔形状?
- compaction的并发策略是怎样的？


```
```

小结：

- L0到L1 compaction不会并发执行
- 每个level有个compaction score和compaction level，并且scoreN <= scoreN-1
- 只要L0->L1有，则不安排L1->L2；i.e. L1要么输入，要么输出，not both
- score >= 1表示需要安排compaction
- LN触发到LN+1的compaction
- 触发compaction的原因有二：L0文件数量超过trigger, L1+文件大小超过最大限制
- L0->L1可能被L0->L1或者L1->L2 block，为了减少stall可能性，尽量开启L0->L0
- L-1可能因为snapshot的释放触发L-1->L-1 compaction，由于清理key的多版本
- rocksdb 2015年添加了SuggestCompactRange API，用来提高空闲时期compaction的aggressive程度

#### PickFileToCompact

- 每次只从start level选一个文件进行compact
- 选择start file的方式是：按照文件从大到小的顺序（只有前50个是顺序)，顺次取文件
- 如果没有找到简单的compaction reason，则尝试删除bottomost文件中的多版本(每个level只有一个?)

pick结果放在以下变量：

start_level_inputs_
compaction_reason_
start_level_
output_level_

#### SetupOtherL0FilesIfNeeded

#### SetupOtherInputsIfNeeded

#### LevelCompactionBuilder

compaction_inputs_
output_level_inputs_
parent_index_
base_index_
grandparents_

#### Compaction

Compaction的要素包括：

- compaction_inputs_
- output_level_
- MaxFileSizeForLevel
- max_compaction_bytes
- pathid
- compression type
- grandparents_
- is_manual_
- start_level_score_
- compaction_reason_




|BackgroundCompaction
|BackgroundCallCompaction
|BackgroundCallFlush
|FlushMemTable
|ContinueBackgroundWork
|CompactRange
    |MaybeScheduleFlushOrCompaction
    |RunManualCompaction
        |BGWorkCompaction
    BackgroundCompaction
        |BGWorkBottomCompaction
            BackgroundCallCompaction
                BackgroundCompaction

#### FlushJob




#### 关于write stall

问题:

- 如何提高compaction的并发度和效率，降低write stall
- 如何提高flush的并发度和效率，降低write stop



手动flush操作会等到flush完成之后再返回。


### Write


## 锁分析

## Tuning Guide

- 从stats可以看出write amp?或者从系统侧观察IO/write_rate
- max_background_flushes max_background_compactions 可以调节后台线程数量


首先flush要能跟上write_rate: 目标tps 1W，数据颗粒8K，则写入速度为80MB/s。
因此flush至少要能写到80MB/s。

由于看到过stop的现象，因此肯定是flush速度不够快。


目前从日志和stats看到的信息就是L0->L1的compaction是瓶颈，这有两个原因：

- L0通常覆盖整个range，因此经常把L1的所有数据量读取出来进行compact
- L0-L1不能并发进行，L0-L1与L1-L2互斥

由于必须单线程顺序逐个compact到L1，最终导致L0的文件数量很多，并最终导致
write delay?

关于compaction的参数：

- 设置L0与L1的大小相同(L0数量在涨，L1的大小与动态数据怎么相同？)
- 设置level multiplier(感觉10应该可以）
- 其他参数

level0_file_num_compaction_trigger（该参数可以用来估计L0大小：write_buffer_size * min_write_buffer_number_to_merge * level0_file_num_compaction_trigger)
max_bytes_for_level_base max_bytes_for_level_multiplier:L1大小和mul,设置为L0大小和10
target_file_size_base target_file_size_multiplier L1单文件大小，Lx单文件涨幅，建议L1 10个文件
compression_per_level由于L0->L1通常是瓶颈，因此L0、L1可以配置为不压缩

### write stall

如果没有write stall，那么会出现文件累积（空间放大增大，磁盘耗尽），读取放大，响应变长。

比较麻烦的是系统可能对写入burst过于敏感，或者低估了硬件能力。

stall的原因：

- memtable 满：硬性限制，直接导致stop
- memtable 将满: 软性限制，stall
- l0 sst 满：硬性限制，level0_stop_writes_trigger
- l0 sst将满: 软性限制，level0_slowdown_writes_trigger
- 待compaction暴多： hard_pending_compaction_bytes
- 待compaction太多： soft_pending_compaction_bytes

一旦出现了stall，rocksdb的write_rate就会下降到delayed_write_rate，并且
如果待compact的数据继续增多，delayed_write_rate 可能进一步下降。

分析日志:

从日志分析来看，最终write_delay_rate居然被限制到只有631kb，那么最后稳定下来之后，最终的写入速率也只有几百tps。

最终的问题是：为什么后台IO落后WRITE那么多，能不能提高？能不能有效地把write-amp保持在32这种级别？

## 性能分析

- 统计read/write/ratelimiter分别耗时多少

write:
    write_wal_time                      11.52
    write_memtable_time                 2.72
    write_delayed_time                  22.86
    write_pre_and_post_process_time     0.86

read:
    get_snapshot_time                   0.18
    get_from_memtable_time              4.19
    get_from_output_files_time          4.55
    get_post_process_time               0.17


- 统计当前磁盘写入是否真的已经到了极限

磁盘性能：

srzhao@phy6319:~$ dd if=/dev/zero of=xx bs=16k count=1024000
1024000+0 records in
1024000+0 records out
16777216000 bytes (17 GB) copied, 26.902 s, 624 MB/

srzhao@phy6319:~$ dd if=/dev/zero of=xx bs=16k count=1024000 oflag=direct
1024000+0 records in
1024000+0 records out
16777216000 bytes (17 GB) copied, 136.855 s, 123 MB/s



## 性能调优

a) 分析

从统计结果看：

    - 有read，不符合预期，减少read应该能提高，或者一点都不提高(因为delay会变多)
    - write_delay占了大部分时间，看看能不能通过别的方法减少write流量

b) 优化

- 压缩

redis-benchmark的value是高度重复的数据，因此压缩之后value的数值很小。

实际测试：

```
srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 5000000 -c 50  -r 100000000 -t set -d 8096
SET: 10820.21(avg) 28796.12(real) through: 462.097992s
====== SET ======
5000000 requests completed in 462.10 seconds
50 parallel clients
8096 bytes payload
keep alive: 1

0.00% <= 1 milliseconds
0.00% <= 2 milliseconds
0.00% <= 3 milliseconds
9.66% <= 4 milliseconds
88.71% <= 5 milliseconds
96.63% <= 6 milliseconds
98.72% <= 7 milliseconds
99.65% <= 8 milliseconds
99.81% <= 9 milliseconds
99.83% <= 10 milliseconds
99.84% <= 11 milliseconds
99.84% <= 12 milliseconds
99.84% <= 13 milliseconds
99.84% <= 14 milliseconds
99.84% <= 15 milliseconds
99.84% <= 16 milliseconds
99.84% <= 17 milliseconds
99.85% <= 18 milliseconds
99.85% <= 19 milliseconds
99.85% <= 20 milliseconds
99.85% <= 21 milliseconds
99.85% <= 22 milliseconds
99.85% <= 23 milliseconds
99.85% <= 24 milliseconds
99.86% <= 25 milliseconds
99.86% <= 26 milliseconds
99.87% <= 27 milliseconds
99.88% <= 28 milliseconds
99.89% <= 29 milliseconds
99.91% <= 30 milliseconds
99.93% <= 31 milliseconds
99.94% <= 32 milliseconds
99.95% <= 33 milliseconds
99.96% <= 34 milliseconds
99.97% <= 35 milliseconds
99.97% <= 36 milliseconds
99.98% <= 37 milliseconds
99.99% <= 38 milliseconds
99.99% <= 39 milliseconds
100.00% <= 40 milliseconds
100.00% <= 41 milliseconds
100.00% <= 42 milliseconds
100.00% <= 43 milliseconds
100.00% <= 43 milliseconds
10820.22 requests per second


srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 5000000 -c 50  -r 100000000 -t set -d 512
SET: 18842.01(avg) 11915.64(real) through: 265.363007s
====== SET ======
5000000 requests completed in 265.36 seconds
50 parallel clients
512 bytes payload
keep alive: 1

0.00% <= 1 milliseconds
0.00% <= 2 milliseconds
94.58% <= 3 milliseconds
98.44% <= 4 milliseconds
99.68% <= 5 milliseconds
99.95% <= 6 milliseconds
99.98% <= 7 milliseconds
99.99% <= 8 milliseconds
99.99% <= 9 milliseconds
99.99% <= 10 milliseconds
99.99% <= 11 milliseconds
99.99% <= 14 milliseconds
99.99% <= 15 milliseconds
99.99% <= 16 milliseconds
99.99% <= 17 milliseconds
99.99% <= 18 milliseconds
99.99% <= 19 milliseconds
99.99% <= 22 milliseconds
99.99% <= 23 milliseconds
99.99% <= 25 milliseconds
99.99% <= 26 milliseconds
99.99% <= 27 milliseconds
99.99% <= 28 milliseconds
99.99% <= 29 milliseconds
99.99% <= 30 milliseconds
99.99% <= 31 milliseconds
99.99% <= 32 milliseconds
99.99% <= 33 milliseconds
99.99% <= 36 milliseconds
99.99% <= 37 milliseconds
99.99% <= 38 milliseconds
99.99% <= 39 milliseconds
99.99% <= 40 milliseconds
100.00% <= 41 milliseconds
100.00% <= 42 milliseconds
100.00% <= 43 milliseconds
100.00% <= 44 milliseconds
100.00% <= 45 milliseconds
100.00% <= 85 milliseconds
100.00% <= 87 milliseconds
100.00% <= 89 milliseconds
100.00% <= 91 milliseconds
100.00% <= 379 milliseconds
100.00% <= 380 milliseconds
100.00% <= 382 milliseconds
100.00% <= 383 milliseconds
100.00% <= 386 milliseconds
18842.11 requests per second


srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 5000000 -c 50  -r 100000000 -t set -d 128
SET: 19461.12(avg) 3072.00(real) through: 256.920990ss
====== SET ======
5000000 requests completed in 256.92 seconds
50 parallel clients
128 bytes payload
keep alive: 1

0.00% <= 1 milliseconds
0.21% <= 2 milliseconds
92.43% <= 3 milliseconds
98.63% <= 4 milliseconds
99.58% <= 5 milliseconds
99.94% <= 6 milliseconds
99.99% <= 7 milliseconds
99.99% <= 8 milliseconds
100.00% <= 9 milliseconds
100.00% <= 10 milliseconds
100.00% <= 11 milliseconds
100.00% <= 13 milliseconds
100.00% <= 14 milliseconds
100.00% <= 17 milliseconds
100.00% <= 18 milliseconds
100.00% <= 19 milliseconds
100.00% <= 20 milliseconds
100.00% <= 21 milliseconds
100.00% <= 23 milliseconds
100.00% <= 25 milliseconds
100.00% <= 27 milliseconds
100.00% <= 28 milliseconds
100.00% <= 29 milliseconds
100.00% <= 30 milliseconds
100.00% <= 31 milliseconds
100.00% <= 32 milliseconds
100.00% <= 33 milliseconds
100.00% <= 34 milliseconds
100.00% <= 36 milliseconds
100.00% <= 37 milliseconds
100.00% <= 38 milliseconds
19461.24 requests per second

```

实际上开启压缩之后，对于redis-benchmark这种案例，冷热分离几乎就是在作弊。
数值备压缩到只有几字节数量。

但是即使在开启压缩，写入没有瓶颈的情况下，长期的性能也只是保持在1W TPS。

在小包(512/128)的情况下，长期性能2W TPS，此时可以看到性能瓶颈就是在单线程
CPU上。

通过perf看到预料之外的性能耗损包括：perf、statistics；Get操作; snappy压缩解压操作;

1) 关闭perf、statistics之后

稳定性能从2W TPS上升到3W TPS. 


```
srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 1000000 -c 50  -r 100000000 -t set -d 128                                                           
SET: 32594.46(avg) 47025.83(real) through: 30.680000s
====== SET ======
1000000 requests completed in 30.68 seconds
50 parallel clients
128 bytes payload
keep alive: 1

0.01% <= 1 milliseconds
97.53% <= 2 milliseconds
99.70% <= 3 milliseconds
99.98% <= 4 milliseconds
99.99% <= 5 milliseconds
99.99% <= 6 milliseconds
100.00% <= 7 milliseconds
100.00% <= 8 milliseconds
100.00% <= 9 milliseconds
100.00% <= 10 milliseconds
100.00% <= 11 milliseconds
100.00% <= 14 milliseconds
32594.52 requests per second
```

2) 关闭snappy压缩

稳定性能从3W TPS上升到3.7W TPS

```
srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 1000000 -c 50  -r 100000000 -t set -d 128
SET: 37566.51(avg) 40021.98(real) through: 26.618999s
====== SET ======
1000000 requests completed in 26.62 seconds
50 parallel clients
128 bytes payload
keep alive: 1

0.01% <= 1 milliseconds
99.09% <= 2 milliseconds
99.78% <= 3 milliseconds
99.99% <= 4 milliseconds
100.00% <= 5 milliseconds
100.00% <= 6 milliseconds
100.00% <= 7 milliseconds
100.00% <= 8 milliseconds
100.00% <= 9 milliseconds
37567.15 requests per second
```

3) 优化Get操作

不使用Get操作确认是否存在原来的数据，可以看到性能能稳定到4.6W TPS。

可以看出此时的性能主要消耗在了crc32和插入memtable RecomputeSpliceLevels上


```
srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 1000000 -c 50  -r 100000000 -t set -d 128
SET: 46080.64(avg) 35019.24(real) through: 21.701000s
====== SET ======
1000000 requests completed in 21.70 seconds
50 parallel clients
128 bytes payload
keep alive: 1

24.29% <= 1 milliseconds
99.32% <= 2 milliseconds
99.84% <= 3 milliseconds
99.99% <= 4 milliseconds
99.99% <= 5 milliseconds
99.99% <= 6 milliseconds
100.00% <= 7 milliseconds
100.00% <= 9 milliseconds
100.00% <= 10 milliseconds
100.00% <= 11 milliseconds
100.00% <= 12 milliseconds
46080.82 requests per second
```
rocksdb::crc32c::ExtendImpl<&rocksdb::crc32c::Slow_CRC32>

> 通过重编rocksdb，enable sse42优化。

rocksdb::InlineSkipList<rocksdb::MemTableRep::KeyComparator const&>::RecomputeSpliceLevels

貌似不成功，效果不明显。

> 应该没有办法优化

4) enable piplined write

pipeline原理：把wal和memtable写入拆分开来，对于某个线程来说，先写wal在写memtable。
但是对于多个线程来说，让leader顺序写wal，然后让follower并发写memtable增大吞吐量。

由于冷热分离单线程，预期该选项无效。

实测结果：如预期，没效果。

```
srzhao@phy6319:~/rks$ redis-benchmark -h 172.18.63.19 -p 33301 -n 5000000 -c 50  -r 100000000 -t set -d 128                                                           
SET: 46424.25(avg) 39718.79(real) through: 107.702003s
====== SET ======
5000000 requests completed in 107.70 seconds
50 parallel clients
128 bytes payload
keep alive: 1

23.72% <= 1 milliseconds
99.71% <= 2 milliseconds
99.92% <= 3 milliseconds
99.99% <= 4 milliseconds
100.00% <= 5 milliseconds
100.00% <= 6 milliseconds
100.00% <= 7 milliseconds
100.00% <= 8 milliseconds
100.00% <= 9 milliseconds
100.00% <= 10 milliseconds
100.00% <= 11 milliseconds
100.00% <= 12 milliseconds
46424.39 requests per second

```

NO COMPRESSION

```
64     | 128    | 256    | 512    | 1024  | 2048  | 4096  | 8192
-----------------------------------------------------------------
45728  | 44714  | 43157  | 42788  | 37937 | 23142 |  4945 | 2677

```

测试结果分析：

- 在数据颗粒小的情况下，性能为4.5W TPS(瓶颈在CPU)
- 在数据颗粒大小为2048时，开始出现后台IO跟不上写入的情况，出现了stall和stop现象, 而且后台出现了长时间的IO落后


SNAPPY COMPRESSION


```
64     | 128    | 256    | 512    | 1024  | 2048  | 4096  | 8192
-----------------------------------------------------------------
57232  | 55665  | 54202  | 45247  | 39694 | 32358 | 16872 | 12784 
```

ZLIB COMPRESSION


```
64     | 128    | 256    | 512    | 1024  | 2048  | 4096  | 8192
-----------------------------------------------------------------
51764  | 51691  | 43388  | 43278  | 42427 | 26587 | 23482 | 7945(stall)

```

结论：

- 压缩比不压缩的写入性能更好，且能够缓解IO跟不上的尴尬
- SNAPPY比libz的性能稍好

b) 如何提高IO上限

- 为什么有些参数不能通过配置文件来控制?


- 怎样让rocksdb写入保持在一个高速、稳定可持续的范围?



为什么半天都不停止compaction，compaction为什么落后write这么多？

写放大到底有多少？

如何调整ratelimiter参数?

max_flushes?




x) 展望

从可行性上分析，SSD磁盘写入速度600MB/s，数据颗粒8k大小，即使写放大5倍，tps也可以到 600MB/8k/5 ~= 1.5W TPS。
而正常一点的数据颗粒1k，则理论上可以达到10W TPS。

可以从以下方面入手：

- 对rocksdb的全面理解(merge op)
- 对on-cpu/off-cpu性能全面分析的能力


-----------------------------
关于options


```
API:

//pointer类型的option需要重新设置（否则为默认）
//不支持以下选项设置
// * comparator
// * prefix_extractor
// * table_factory
// * merge_operator
LoadOptionsFromFile



DS:



```














