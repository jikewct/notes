# redis-sentinel 

redis-sentinel <conf>
redis-server <conf> --sentinel 

## 启动

与redis-server相同，redis-sentinel在启动过程中：

- 初始化数据结构
- 配置文件加载
- 监听端口，注册事件（unixAcceptHandler, tcpAcceptHandler, serverCron, beforSleep)

不同的是

- sentinel 初始化将清空redis命令列表，替换成sentinel列表
- sentinel 有一个100ms的sentinelTimer Cron
- 

## api

sentinel pending-scripts

## 问题

在sentinel.conf中配置 slaveof, appendonly, save 什么的居然有效。
所以需要注意的是修改代码时需要注意修改的也包括sentinel。

--------------

ailover时发送的命令包括

MULTI
slaveof <host> <port>
config rewrite
client kill type normal
EXEC


导致了upredis-2.0版本出现:
MULTI/EXEC以及中间的文件



