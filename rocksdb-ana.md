#format markdown

# 关于rocksdb的分享

## 总体框架

![rocksdb](rocksdb.png)


### 模块组织

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


### 文件组织

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

### 操作

| ------        | ------------------------------------------------------------          |
| switch        | Memtable和WAL切换;切换时WAL切换新文件和mm-->imm;WAL或者mm full时触发switch操作。          |
| flush         | 将imm写入到sst文件；超过max_write_buffer_number将触发flush操作；flush操作由threadpool执行 |
| minor compact | level0-->level1（与major compact不同的是level0文件key范围可重叠)                          |
| major compact | levelN-->levelN+1，N>=1                                                                   |

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

```
## options分析

## MVCC

## 事务模型

## 数据库恢复

## 线程模型

## 并发控制

## 统计信息

## 无锁编程

```
