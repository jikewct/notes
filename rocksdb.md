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



