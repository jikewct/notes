# kafka

使用的场景包括log aggregation, queuing, and real time monitoring and event processing。

## 概念

broker
topic
patrition
rep-factor
ISR
HW

## 功能

- 如何保证消息不丢？

kafka consumer需要定期ack。

- 是否具有延迟消费功能？

有timing wheel。

## 性能测试

2个broker部署在同一个节点172.18.63.19。

测试命令：

./bin/kafka-console-producer.sh config/producer.properties --topic syncrepl --broker-list 127.0.0.1:9091,127.0.0.1:9092,127.0.0.1:9094 


- 1 topic/1 partition/2 repl/record-size 500/[acks=all, batch.size=0, nofsync]

```
5607 records sent, 1121.4 records/sec (0.53 MB/sec), 50971.9 ms avg latency, 51021.0 max latency.
```

23个produce-perf，性能为26450(1150x23) TPS.

- 1 topic/1 partition/2 repl/record-size 500/[acks=1, batch.size=0, nofsync]

```
9759 records sent, 1951.8 records/sec (0.93 MB/sec), 28939.2 ms avg latency, 29100.0 max latency.
9878 records sent, 1975.6 records/sec (0.94 MB/sec), 29108.2 ms avg latency, 29178.0 max latency.
9594 records sent, 1918.8 records/sec (0.91 MB/sec), 29261.1 ms avg latency, 29342.0 max latency.
```

23个produce-perf，性能为44850(1950x23) TPS.

- 1 topic/1 partition/2 repl/record-size 500/[acks=0, batch.size=0, nofsync]


```
11198 records sent, 2210.4 records/sec (1.05 MB/sec), 25844.2 ms avg latency, 25999.0 max latency.
11089 records sent, 2205.0 records/sec (1.05 MB/sec), 25872.0 ms avg latency, 26022.0 max latency.
11134 records sent, 2183.1 records/sec (1.04 MB/sec), 25934.1 ms avg latency, 26083.0 max latency.
```

23个produce-perf，性能为44850(50600) TPS.

- 1 topic/1 partition/2 repl/record-size 500/[acks=0, batch.size=0, nofsync]

```
4416 records sent, 798.4 records/sec (0.38 MB/sec), 29530.6 ms avg latency, 32710.0 max latency
119808 records sent, 23847.1 records/sec (11.37 MB/sec), 2779.2 ms avg latency, 2949.0 max latency.
120160 records sent, 23912.4 records/sec (11.40 MB/sec), 2729.7 ms avg latency, 2866.0 max latency.
4736 records sent, 887.1 records/sec (0.42 MB/sec), 30238.1 ms avg latency, 33307.0 max latency.
120352 records sent, 23998.4 records/sec (11.44 MB/sec), 2761.4 ms avg latency, 3063.0 max latency.
119968 records sent, 23921.8 records/sec (11.41 MB/sec), 2754.3 ms avg latency, 3041.0 max latency.
4576 records sent, 830.9 records/sec (0.40 MB/sec), 34681.9 ms avg latency, 36260.0 max latency.
115776 records sent, 23090.5 records/sec (11.01 MB/sec), 2864.6 ms avg latency, 3163.0 max latency.
143328 records sent, 28585.6 records/sec (13.63 MB/sec), 2356.3 ms avg latency, 2758.0 max latency.
142112 records sent, 28343.0 records/sec (13.52 MB/sec), 2375.2 ms avg latency, 2763.0 max latency.
2240 records sent, 439.9 records/sec (0.21 MB/sec), 39749.9 ms avg latency, 42602.0 max latency.
141376 records sent, 28190.6 records/sec (13.44 MB/sec), 2375.8 ms avg latency, 2751.0 max latency.
143968 records sent, 28713.2 records/sec (13.69 MB/sec), 2343.5 ms avg latency, 2720.0 max latency.
2368 records sent, 443.2 records/sec (0.21 MB/sec), 39326.6 ms avg latency, 40780.0 max latency.
126976 records sent, 25364.8 records/sec (12.09 MB/sec), 2747.0 ms avg latency, 3145.0 max latency.
133440 records sent, 26608.2 records/sec (12.69 MB/sec), 2626.0 ms avg latency, 2947.0 max latency.
133472 records sent, 26694.4 records/sec (12.73 MB/sec), 2484.1 ms avg latency, 2738.0 max latency.
1888 records sent, 340.9 records/sec (0.16 MB/sec), 40747.4 ms avg latency, 44679.0 max latency.
136672 records sent, 27328.9 records/sec (13.03 MB/sec), 2471.5 ms avg latency, 2873.0 max latency.
1248 records sent, 232.1 records/sec (0.11 MB/sec), 44635.3 ms avg latency, 47864.0 max latency.
134432 records sent, 26881.0 records/sec (12.82 MB/sec), 2390.9 ms avg latency, 2604.0 max latency.
128768 records sent, 25753.6 records/sec (12.28 MB/sec), 2501.9 ms avg latency, 2674.0 max latency.
1568 records sent, 313.3 records/sec (0.15 MB/sec), 51619.0 ms avg latency, 54162.0 max latency.
```

23个produce-perf，性能为:798+23847+23912+887+23998+23921+830+23090+28585+28343+439+28190+28713+443+25364+26608+26694+340+27328+232+26881+25753+313
395509 TPS。此时的性能瓶颈为单机的磁盘性能。


## 问题

- 三个broker怎么知道是属于一个cluster的？
:: cluster不是broker级别的概念，而是partition级别的概念，因此不需要指定broker属于哪个cluster

- 选择分片哈希是客户端做的？

- 使得kafka进入undersync状态的log有没有被commit ?



## 参考材料

[1, Jun Rao] https://engineering.linkedin.com/kafka/intra-cluster-replication-apache-kafka


# redis stream

## 业界竞品

https://bbs.huaweicloud.com/community/trends/id_1502254974847043
http://queues.io/

C:

disque
beanstalkd
ZEROMQ
nanomsg/nng

rocksdb/leveldb:
kafka streams
Siberite
ZippyDB 
Iron.io


# disque

分布式内存任务队列。

## API

```
ADDJOB queue_name job <ms-timeout> [REPLICATE <count>] [DELAY <sec>] [RETRY <sec>] [TTL <sec>] [MAXLEN <count>] [ASYNC]
GETJOB [NOHANG] [TIMEOUT <ms-timeout>] [COUNT <count>] [WITHCOUNTERS] FROM queue1 queue2 ... queueN
ACKJOB jobid1 jobid2 ... jobidN
FASTACK jobid1 jobid2 ... jobidN
WORKING jobid
NACK <job-id> ... <job-id>

INFO
HELLO
QLEN <queue-name>
QSTAT <queue-name>
QPEEK <queue-name> <count>
ENQUEUE <job-id> ... <job-id>
DEQUEUE <job-id> ... <job-id>
DELJOB <job-id> ... <job-id>
SHOW <job-id>
QSCAN [COUNT <count>] [BUSYLOOP] [MINLEN <len>] [MAXLEN <len>] [IMPORTRATE <rate>]
JSCAN [<cursor>] [COUNT <count>] [BUSYLOOP] [QUEUE <queue>] [STATE <state1> STATE <state2> ... STATE <stateN>] [REPLY all|id]
PAUSE <queue-name> option1 [option2 ... optionN]
```

## 设计

- 为啥ttl/delay/retry需要设置在job级别而不是queue级别?

job会被复制到多个node，但是通常只在一个node入队(queued)

生产：

消费:

requeue:

ACK&GC:

分区：

持久化：



## 代码分析

### ADDJOB

<ms-timeout>: 命令超时时间，如果指定时间之内没有复制到指定的副本上，命令返回`-NOREPL`
REPLICATE: 副本数量
DELAY: 延迟指定时间，然后再enque
RETRY: 经过指定时间后没有ACK的job将被重新enque
TTL:
ASYNC:
MAXLEN:

### GETJOB

### ACKJOB

### FASKACK

## 分布式设计

- 支持事务？
- 最终一致的AP系统？
- 不丢不重?
- 内存超量问题？
- 节点数量不满足repl-factor怎么办？
- 脑裂问题？
- 均衡、本地化问题？

## 启发



# beanstalkd

- 目前基本已经不发展
- 可以开启持久化
- 分布式是通过客户端实现(和memcached的分布式设计思路类似)
- 没有复制和高可用方案

基本上不可能作为金融级消息队列的备选方案。

# ZeroMQ

- 高层的socket通信库，用法类似于socket
- 非broker，感觉定位更加类似于mtq

# nng

- 与libnanomsg&zeromq类似，都是broker-less的通信库


# 结论

关于分布式消息队列可能从以下两个方向考虑：

- 升级redis基线版本，引入stream特性，并且通过rocksdb解决成本问题
- 基于disque做开发，把上游的bug修复，引入rocksdb持久化解决成本问题

disque是(EC)AP系统，副本的利用率更高，理论上是一个更优的架构
stream是(OC)AP系统，副本价格高，但是使用上更加接近kafka的语义


