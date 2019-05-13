# nemo-rocksdb

处理延迟删除和超时。

## 概要设计


```
|meta key|   |meta value|version|timestamp|
|node key|   |node value|version|timestamp|
```

在node，meta对应的value上添加version和ttl:

超时：

- timestamp超过当前时间则超时

延迟删除：

- meta.version > node.version说明node已经被删除 
- 为了实现延迟删除，nemo-rocksdb需要知道node和meta的对应（无法抽象到key/value）
- 如果在nemo中实现延迟删除，那么需要重复实现类似的逻辑多次，并且不太容易做到compaction删除已经被删除的nodes？

用法：

- 构造好writebatch之后，最后根据需要调用相应的Writexx方法

get: 

```
if node:
    if node.version < meta.version:
        node already deleted
    else
        node exists
else:
    meta exists

```

put: 

```
if node:
    node.version = meta.version
    put node-key node|version|ts
else:
    meta.version = meta.version
    put meta-key meta|version|ts

```

del: //删除node

```
if node:
    del directly
else:
    //we never del meta?

```

unlink: //删除整个key

```
if node:
    //we never unlink node
else:
    meta.version++
    put meta|version|ttl
```

- meta version一定是最新的version，所以在write with ttl中可以直接采用meta的version

问题：

- unlink的用法啥样？传入的metaval是啥？
- del能不能用来delete meta？
- meta一旦出现，就不可能再删除了？如果要删除，则compaction filter中需要理解meta的组成和意义，并且给出相应的删除方法？



如何把rks与db-nemo结合起来?

## DBNemoImpl

nemo-rocksdb负责encode/decode version和ttl，不负责encode/decode meta，node。

总体设计思路：迭代、编码、更新wb、写入更新的wb。

- writebatch的可以按照ttl、ts、version相同写入
- version起始值为time(NULL)
- 如果meta超时，则nodes也超时（注意不要造成复活）
- merge的operand的version和ttl都是0：不超时，没有版本？

```
GetVersionAndTS         //获取nodekey或者metakey对应的metaval的version和ts（kv本身就是meta，因此
AppendVersionAndTS      //添加version和ts：注意传入参数为ttl
AppendVersionAndExpiredTime //添加version和expiredtime
Write(WithTtl)          //
WriteWithExpiredTime    //
WriteWithKeyVersion     //wb中中每个node，meta都会被添加一个新的版本（time(NULL)或者version_old++)
WriteWithOldKeyTTL      //保持和meta一样的version和超时，如果meta已经超时，则version++&不超时
```

## NemoIterator

考虑了version和ttl的迭代器。

node的version和ttl可能是上一个已经超时或者被延迟删除的，但是meta的version和
ttl总是最新的。如果是meta，直接对比自己的ttl和version；如果是node，则和meta
的ttl&version对比。


```
ExtractVersionAndTS
ExtractUserKey
GetVersionAndTS
```

## NemoCompactionFilter

NemoCompactionFilter是必要的！否则无法清除掉过期数据造成空间浪费。

支持用户传入usr_compaction_filter,user_comp_filter_from_factory，并且优先使用前者。
过滤时先使用usr_compaction_filter过滤一遍。


```
ShouldDrop  //meta.card == 0，meta stale，node stale，node.ver < meta.ver，node没有对应的meta
```

## NemoCompactionFilterFactory

持有user_comp_filter_factory_，并且使用该factory获取cf，用于初始化NemoCompactionFilter.

## NemoMergeOperator

千辛万苦就是为了让usr_merge_operator能够在没有version和ttl的干扰下执行merge。

## DBNemoCheckpoint

get不到checkpoint存在的意义？
难道再尝试解决不flush但是可以获取当前的大小的问题？
至少一个变化时link wal。
无论如何对于upredis-rks的意义不大，因为我们通过上报seq获取checkpoint的seq。


## 对接uprocks

- 接口扩展问题
- 确认每一个meta的第一个元素都是length/card之类的含义，否则逻辑有问题
- 实现超时和del动作


问题：

为什么全局变量?
g_compaction_filter_factory
g_compaction_filter

# nemo

## scan方案

主要思路是在内存中保存了一个cursor->start_key的映射。


```
//保存了{cursor:startkey}映射的lru缓存
cursors_store_ := (
    lsit_ := [ cursor ]
    map_ := { cursor: startkey }
    max_size_
    cur_size_
)
```


# pika

线程模型依赖于pink


## pink threads

一个dispatcher thread，多个worker thread，每个thread有一个 epoll loop。

- Thread 基础的线程类，提供线程启动，暂停，初始化，join等基本功能
- ServerThread->Thread: 服务器（accept）线程；提供了一般服务器的框架；+ServerHandle，定义Server接收到链接之后的行为
- WorkerThread->Thread: worker（rw）线程：提供了链接rw的框架；通过PinkConn的SendReply，GetRequest进行自定义行为
- DispatchThread->ServerThread 实现了ServerThread里面的一些莫名其妙的virtual函数;
-  RedisConn/PbConn分别表示redis协议的的处理和protobuf的处理；


总结下：
dispatcher-worker处理accept，分发fd；ServerHandle是钩子，默认为nullptr；
serverloop使用ServerHandel钩子
workerloop使用Conn的发生读写调用getRequest和sendReply；
redisconn/pbconn都有DealMessage纯虚函数，相当twemproxy的parse_done


## pika

- pika只需要处理与客户端的连接，client的DealMessage
- redis-conn直接把命令全都处理到argv中了, 然后就是DoCmd(argv[0])
- cmd中三个函数：Initial，Do，ToBinlog会在DoCmd中被调用；因此每个cmd都override以上三个函数就可以了
- DoCmd的res.message保存了要回复到client的消息

## pika-list

接口 LINDEX LINSERT   LLEN  LPOP   LPUSH LPUSHX LRANGE     LREM LSET LTRIM
状态 o      o         o     o      o     o      o          o    o    o
接口 RPOP   RPOPLPUSH RPUSH RPUSHX BLPOP BRPOP  BRPOPLPUSH
状态 o      o         o     o      x     x      x

命令：
LPUSHX - 队列非空，然后再push一个
LTRIM - 修剪
RPOPLPUSH - 原子性地移动元素
LSET key index value

存储格式：

包含两部分：list（元信息)和list_node(节点信息）

list:

(L|key|version|ttl) (len|left_seq|right_seq|cur_seq)

list_node:

(l|size|key|seq) (pre_seq|next_seq|value|version|ttl)


pika并不是直接在cmd层对command做了解析执行，而是将cmd代理到nemo存储引擎。cmd代理层做了检查和数据
准备工作。

## pika-nemo

nemo可以看成是rocksdb版本的redis（但是不提供协议解析功能）

- nemo为什么持有list_db，hash_db_等多个db，为什么不是一个？
- nemo为什么持有多个record_mutex，而不是一个？为什么需要记录锁？

基本上可以认为现在已经具备了像nemo一样进行rocksdb开发的知识。

- c binding

## knowledge

- virtual/override virtual声明函数可以被重写；override明确函数是重写 函数（用来做编译期检查）
- const成员函数：该函数不会对成员进行修改
- virtual foo() = 0; 纯虚函数，对于非abstract类来说，必须实现纯虚函数
- CLOEXEC close-on-exec
- 由于c++支持多继承，因此为了像java，c#一样调用super.xx/base.xx；c++使用BaseClass::xx消除歧意
- friend的意思是允许别的类访问修改本类的私有数据，这样的话也就不用每个属性都public或者set/get
- using StackableDB::Put


-----------------------------
为什么ttl？version？多个db？是不是和column family类似？为什么需要recordmutex？
mergeCF是干嘛使得？merge的整个框架是什么样的？

::pika的kv，hash，zset, set , list的meta_prefix_分别为'\0', 'H', 'Z', 'S', 'L'
::多个db并不是物理上的多个db，而是同一个物理db打开了多次，分别用于不同类型的数据
::因为writebatch在读不需要互斥，但是写需要互斥
::merge操作对于nemo来讲简直太重要了，因为nemo大量的是修改version？


------------------------------
关于merge的一些疑问：
- 客户端怎么使用merge？主动调用还是被动调用？怎么自定义merge_operator？一般什么场景会自定义merge_operator？
- 会不会被动调用merge operator
- rocksdb关于merge的设计是什么原理？为什么要这么设计？
- merge 与 compaction 有没有关联

::客户端通过db->Merge主动调用Merge函数，触发Merge操作
::db持有option，option持有mop，因此db持有mop；客户端继承mop，覆盖其中的FullMerge or FullMergeV2 and 
optionally PartialMerge ；rocksdb通过
::
:: merge与compaction有关联，事实上merge与get/snapshot/compaction都有关系，因为merge引发了不确定性。由此
可见，设计一个东西是比较有难度的！要是我设计，肯定中途就退缩了，或者苦于找不到解决方案就放弃了。


----------------------------
关于column family（cf）
- 使用方式？
- 设计思路？


::使用方式
新增cf：db->CreateColumnFamilily(options, "new_cf", &cf);
删除cf: db->DropColumnFamiliy(cf);

打开cf：
cfds.push_back(ColumnFamilyDescriptor("new_cf", ColumnFamilyOptions));
DB::Open(options, "/tmp", cfds, &cfs, &db)

使用cf：
db->Put(options, cf, k, v);
db->Get(options, cf, k, &v);

NOTE：使用rw模式打开db时，需要传入所有的cf，否则打开失败；r模式可以传入部分cf；

:: 设计思路：


------------------------------
关于Merge Operator
由于有了mop，所以get必须执行了merge之后才能获取最新的版本

Get(key):

stack = []
for opi from newest to oldest
    if opi is "merge"
        push opi to stack
        while stack.size >= 2:
            l = stack.pop
            r = stack.pop
            push mop.PartialMerge(l,r) to stack
    else if opi is put:
        return mop.FullMerge(v, stack)
    else if opi is delete:
        return mop.FullMerge(nullptr, stack);

return mop.FullMerge(nullptr, stack)

-------------------------------

关于mop的原理性描述：

https://github.com/facebook/rocksdb/wiki/Merge-Operator-Implementation

本文讲的非常棒！


:: PartialMerge的前提是mop满足结合率，mop标记为*

(a*b)*c = a*(b*c)是PartialMerge的前提，如果我们的操作并不满足ssociativity，则无需定义PartialMerge

------------------------------

TTL

真的只是一个全局的参数！意思是在本次Open的db中所有的数据将在更新后ttl之后失效。


---------------------------
一些问题：

关于nemo-rocksdb:
- db->put是不是应该修改为merge（mop：write with old ttl）？如果全部put转换为merge，则大量的merge导致get效率下降？
- db->write(batch, ttl)这种格式写，整个batch共享一个ttl，而不是每个k一个ttl？还是很奇怪
- 关于nemo-rocksdb的使用方式，设计逻辑？

使用方式
db->Put(o,k,v,ttl)
db->PutWithKeyVersion(o,k,v)?
db->GetKeyTTL(o,k,&ttl) 

batch->Write(o,b,ttl)
db->WriteWithOldKeyTTL(o,b)


删除的时候调用了list_db_->PutWithKeyVersion on metakey，实际上调用的b->put;b->WriteWithKeyVersion；

:: 之所以Handler中有MergeCF是因为batch中的操作可能包括merge呀！put，del，get，merge四中基本操作，其中put/del/merge
是需要重写（实际上Handler需要重写的函数很多，没有重写的操作不支持）


所以最终在

---------------------------

为什么StackableDB继承了DB之后，还需要持有DB？


---------------------------

对比四种写的区别

Write(WithTTL):

WriteWithExpiredTime

WriteWithKeyVersion
??
只要当前key已经过期，那么当前key的ver++，然后在写进去；
因为每次都是在meta上操作，所以就相当于抛弃了所有的旧版本数据。
所以说这个功能必须要compaction支持，因为如果compaction的时候如果不支持，
那么这样做就不是一般的写放大了。

WriteWithOldKeyTTL

区别对待了kv，kv直接没有ver，ts；

GetVersionAndTS

对meta和普通key进行了区分对待，metakey的value含有起TS和version；
普通key，必须要拼上meta_prefix_和key之后再获取value中才有ts和ver；

这样看来其实pika的wiki上描述的是准确的。

真的搞了5个db来分别存储五种数据结构

如果data ver < meta ver 说明data已经old version
如果ts < now 说明已经 stale

nemo-rocksdb有点类似于这个协议栈这种模式，越往高层拿到的东西越少

- GetVersionAndTS时获取的是meta的key和version!
- kv没有ver和ts, 这是为什么？
- ver的含义是什么？

----------------------------
问题：
- 为什么要在每个value后面添加ver和ts, meta添加不就好了？
- kv 为什么不需要ver和ts？
- ver和ts对于性能的影响性分析
- 如果是参考协议栈这种设计思路的话，为什么ttl层还需要知道应用层的类型！！感觉设计者是不是有点头脑不清晰！

--------------------------
对nemo-rocksdb的总结
- wiki上的描述不十分准确！
= data ver < meta ver : data old, meta ts < now key stale;
------------------------
- ttl怎么使用mergeop的？为啥需要user_merge_operator ?
:: 
- 怎么使用compaction filte？r为什么需要user_compact_filter ?
::
g_compaction_filter, 
options->compaction_filter，
g_compaction_filter_factory,
options->compaction_filter_factory
options->merge_operator
居然是设置了DB和MP就完了？干嘛呀？

综上：通过db->options->compaction_filter_factory或者compaction_filter持有
factory，调用compact方法。

通过db->options->merge_operator访问merge

之所以使用user_compact_filter是因为用户也可能有调用merge的需求。

- kv有没有ttl? 如果没有kv没有ttl，那么怎么让compaction filter过滤过期kv呢？






