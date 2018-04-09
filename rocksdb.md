# 关于rocksdb

基于leveldb并对于flash存储进行了优化一个kv存储引擎。

- rocksdb能提供WAF，RAF，SAF之间灵活的平衡；
- 多线程compact，适合单库大数据

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

- fdatasync比fsync快
- DB, put, get, getIt线程安全，但是writebatch以及iterate非线程安全



--------------------------------------------------

基本操作：
- Put, Delete, Get
- WriteBatch Write
- MergeOperator read-modify-write merge给出了一种自定义incremental updates的方法


-------------------------------------------------
代码研读：

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


-------------------
# rocksdb阅读

## c bindings
- Static函数绑定最直接，成员函数绑定第一个参数为Object，override通过函数指针，overload通过不同函数名

暴露出的概念：db, backup_engine, checkpoint, column family, iterator, snapshot, compact
              writebatch, writebatch_index,  block_based_option, cucoo, options, bulkload,
              ratelimiter, comparator, filterpolicy, MergeOperator, sync/flush, cache, env
              sst, slicetransform, universal/fifo/level compaction, transaction


## db

- db线程安全
- level0 stop write?
- flush?
- 组成部分：table_cache, memtables, directories(db, data,wal), write_buffer_manager, 
    write_thread, write_controller, rate_limiter, flush_scheduler, snapshots, pending_outputs?,
    flush_queue_, compaction_queue_, purge_queue_, mannual_compaction_queue, wal_manager,
    event_logger_, super_version_?, versions_, db_name_, env_, db_options(initial, mutable, immutable)
    stats_, recovered_transactions_, 

## 具体分析


options {
    db_options {
        immutable_options
        immutable_options
    }
    cf_options;
}

从put和get分析

WriteBatch::Put：
1. savepoint s(b)
2. b.count++
3. b->rep_构造
4. 设置content_flag |= HAVE_PUT
5. s.commit()

6. LocalSavePoint: ?


DBImpl::Write

- pipelined?

1. Write w;
2. write_thread_.JoinBatchGroup
    - oldest_writer为group leader
    - 多线程LinkOne采用了atomic::compare_and_exchange指令，避免使用锁
    - WriteThread::Writer

2.1 as leader
    - PreProcessWrite [处理wal，writebuffer满等先决条件]
    - EnterAsGroupLeader [形成writ_group，也就是得到(newest oldest]]
    - WriteWAL  [为什么需要多个logs_? 大约就是tmp_batch_.Append, log_writer_.AddRecord, Sync]
    - InsertInto [如果没有什么高级操作（inplace_update）那么，insertinto就是memtable-Add]
    - MarkLogsSynced
    - CompleteParallelMemTableWriter
    - ExitAsBatchGroupLeader





3. 根据不同的state进行写入
    - STATE_PARALLEL_MEMTABLE_WRITER 
    - STATE_COMPLETE
    - STATE_GROUP_LEADER


对rocksdb的分析确认了之前关于硬盘读写的认知：
- 多线程对磁盘写并不会有任何帮助
- 

二手资料显示：
single writer模式：所有的writer排队，只有队列头的writer可写（其他writer等待）。


关于memtable:
Add: 与map.add的语义类似






关于atomic的memory order的理解：

compare_and_exchage
load and store
cond_var

---------------------------------
memory order
卧槽，太复杂


---------------------------------

1. JoinBatchGroup
- 多线程writer合并为single writer
- leader执行写，follower都看着


2. PreProcessWrite
- handle wal full: flush oldest cf
- handle writebuffer full: flush largest cf

3. EnterAsGroupLeader
- 准备write group(aka tmp_batch_)

4. WriteToWAL
- 写WAL

5. InsertInto
- 写memtable

6. 退出清理
- ?







