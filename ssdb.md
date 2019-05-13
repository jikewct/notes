
# ssdb

- 兼容redis协议和更加简单的ssdb协议
- 使用leveldb作为引擎，磁盘存储
- 与redis数据结构不完全兼容，不支持set结构
- 对redis命令支持度不高(keys,scan均不支持)，命令与redis并非一一对应,dbsize与redis的含义不同，表示的是占用的磁盘量，没有dbsize命令, scan也是采用了rocksdb的range(小样，很变通啊！）
- 通过twemproxy代理实现分片方案和集群方案

不支持的redis特性：

- lua
- 高可用
- sentinel

总体来讲ideawu的选择倾向于简单优雅直接灵活不强求。

## encoding

kv

|'k'|key|

hash

'h'

zset

|'Z'|key|
|'s'|keylen|key|member|
|'z'|keylen|key|score|

queue

|'Q'|key|
|'q'|keylen|key|seq|

## 总体设计

- binlog代表了writebatch
- 为了兼容redis的api，同样也要read-update-write，降低了整体吞吐量

## ssdb vs redis


# pika

- 兼容redis协议，支持大部分API
- 使用rocksdb为引擎，通过twemproxy支持分片
- 支持**双主**、主从、sentinel高可用

不支持的redis特性：

- lua和事务



