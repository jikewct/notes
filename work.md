# 2018-06-12

# 2018-06-13

# 2018-06-14

苗博issue
cvs代码提交
变更信息提交
编译
代码清理review

关于编译的材料：

https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/developer_guide/gcc-compiling-code#gcc-compiling-code_understanding-relationship-code-forms-gcc
https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/developer_guide/gcc-using-libraries#gcc-using-libraries_using-both-static-dynamic-library-gcc
https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/developer_guide/gcc-using-libraries

# 2018-06-19

# 20180625

梳理propagate

例会

无卡业务团队 李俊 UPREDIS
咨询关于rmt性能

云闪付团队 江之洋 UPREDIS
咨询关于upredis-api-c的客户端密码用法错误支持

接入应用团队 刘宾 UPREDIS
咨询upredis-api-c预连接数数量控制

接入应用团队 刘宾 UPREDIS
评审AM业务迁移方案

技术支持团队 蔡江 UPREDIS
咨询upredis-proxy对pub/sub的支持以及相关文档

rocksdb方案与后续工作整理规划


# 20180904

## 单元测试

```
▼ type/
o   hash.tcl
o   list-2.tcl
o   list-3.tcl
o   list-common.tcl
o   list.tcl
o   set.tcl
o   zset.tcl
o aofrw.tcl #disable
o auth.tcl
o basic.tcl #部分不支持命令被rdsonly
o bitops.tcl
o dump.tcl #disable
o expire.tcl
o hyperloglog.tcl #disable
o introspection.tcl #select不受支持,rdsonly
o latency-monitor.tcl
o limits.tcl
o maxmemory.tcl
o memefficiency.tcl
o multi.tcl
o obuf-limits.tcl
o other.tcl # 目前太多问题
o printver.tcl
o protocol.tcl
o pubsub.tcl #TODO
o quit.tcl
o scan.tcl
o scripting.tcl
o slowlog.tcl
o sort.tcl #disable
```

## 集成测试


### 持久化

如果开启了rksmode，那么持久化由rks负责，其他

### 复制

一主一从模式

一主多从模式



```
      aof-race.tcl
      aof.tcl
      convert-zipmap-hash-on-load.tcl
      rdb.tcl
      redis-cli.tcl
      replication-2.tcl
      replication-3.tcl
      replication-4.tcl
      replication-abnormal.tcl
      replication-hash-cmd.tcl
      replication-hyperloglog-cmd.tcl
      replication-key-cmd.tcl
      replication-list-cmd.tcl
      replication-lua-cmd.tcl
      replication-multi-slave.tcl
      replication-psync.tcl
      replication-server-cmd.tcl
      replication-set-cmd.tcl
      replication-sortedset-cmd.tcl
      replication-special.tcl
      replication-string-cmd.tcl
      replication.tcl
```


## 覆盖率与内存泄露


## 支持multiple db

flushall flushdb dbsize分析
cursormap 倾向于把cursormap放在redisdb，每个db都有一个独立的cursormap，这样不需要修改太多，逻辑上也讲得通
pinned 是个啥？
hash list改成支持cf


检查未调用r_lookupkey的hash，list对于expire的处理

为什么randomkey从m开始没有检查是否迭代到了set？

确认zset中的Add产生的delete会不会造成dbsize统计错误!

uprocks能不能保证迭代器不会把dbsize x____DBSIZE____ 给迭代到，删除又怎么能保证dbsize能被reset？ flushall，flushdb与dbsize的兼容测试


## fix

|replicationSetMaster
|replicationUnsetMaster
|disconnectSlaves
    freeClient


|replicationSetupSlaveForFullResync
|masterTryPartialResynchronization
    freeClientAsync
