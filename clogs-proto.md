# clogs 报文格式

clogs采用udp协议进行通信，客户端和服务端通信报文分为clogs报文和ping/pong报文两种。

- clogs报文为客户端向服务端发送的待脱敏报文
- ping/pong报文为客户端与服务端之间的探测报文

## clogs报文

clogs报文：clogs报文头 +  通信报文


```
/*
 *   clog报文:
 *  +---------+----------------------------------------------------------------+
 *  |  clen   |sys_id｜msg_type|filename|head_len|reserverd|  mlen |msg(binary)|
 *  +---------+----------------------------------------------------------------+
 *  |         |       <--       clog_info       -->        |       |<-- msg -->|
 *  |  <--------                    clogs                      --------->      |
 *
 *  (NOTE: 除msg，以上各域均cstirng表示)
 *  clen        : ==5B : clogs报文的总太小,表示范围为 0-9999
 *  sys_id      : <=5B : 子系统代码, 如"MAPS"
 *  msg_type    : <=5B : 消息类型，如"MS01"；子系统内唯一
 *  filename    ：<=17B: 日志文件名称
 *  head_len    : VAR  : 报文头长度:每个系统自己添加的报文头长度
 *  reserved    ：<=80B: reserved
 *  mlen        : VAR  : msg的大小
 *  msg         ：VAR  ：待脱敏消息
 */
```

## ping/pong报文

ping报文:客户端向服务端发送的探测报文
pong报文:服务端向客户端发送的回复报文

```
/* 
 * ping/pong 报文:
 * +------------+
 * |'P' |  id   |
 * +------------+
 * | 1B |  4B   |
 *
 * 'P'      : magic number
 *  id      : ping_id/pong_id, 其中pong_id == ping_id + 1时说明服务端正常
 *
 */
```