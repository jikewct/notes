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







