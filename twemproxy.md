

upredis在2.2.0之前的upstream为 twemproxy-bf9803b

# 上游追踪

bf9803b..v0.4.1

- ef45313  mark server as failed on protocol level transiet failures like -OOM, -LOADING, -BUSY
proxy可以将LOADING, BUSY, OOM类型的redis返回一个通用的错误，并且能够自动隔离该redis。

upredis-proxy基本不使用auto_eject, 该patch对于upredis-proxy没有用处，反而隐藏了更多的信息。

- ea7190b 日志调整
- b9b985a, 5c897fb memcached
- 5b04fee 使用sockinfo替代family, addrlen, addr
- f9b688e test调整
- 8aeb6f3 rbtree代码reorg
- d3c19ad getaddrinfo returns non-zero +ve value on error，error判断调整，没啥影响
- fd34c29 lazy resolve，upredis-proxy也不用hostname，所以没影响
- 00def85 7e04cd8  注释调整
- 12b5a66 变量名调整
- cae528d cf4ea73 变量调整
- cbaced3 函数名调整
- d2e1721 调整是否需要auth的判断时机
- fc0be81 调整了require_auth的判断方法 
- 7e50f0c adf00c8 调整CHANGELOG spec


v0.4.1..c5c725d

- ba06d32 修复yaml value为null时proxy coredump
- 5f3098a 添加tcpkeepalive选项（解决虚链接问题）
- 6dc1e45 添加bitpos支持
- 0f69053 client_connections docuemtn
- 141e621 6885783 spop在3.2增加了count参数，所以twemproxy需要对应修改。
- 其他基本都是对README的修改和typo fix


upredis-2.2.0 引入5f3098a(keepalive),6dc1e45(bitops),141e621/6885783(spop)


# twemproxy异步框架

未使用外部组件，twemproxy实现一个内部异步框架。

## 总体设计

- 单进程单线程，多路复用(epoll/kqueue/evport)管理多个链接
- twemproxy进程一个`event_base`，一个`epoll fd`, 一个`event_cb`(`core_core`)
- `event_wait`等待事件触发后，调用`core_core(conn, events)`(conn存储在多路复用函数的privdata)处理相应事件

## API

```
//创建销毁event_base
struct event_base *event_base_create(int size, event_cb_t cb);
void event_base_destroy(struct event_base *evb);

//添加删除事件
int event_add_in(struct event_base *evb, struct conn *c);
int event_del_in(struct event_base *evb, struct conn *c);
int event_add_out(struct event_base *evb, struct conn *c);
int event_del_out(struct event_base *evb, struct conn *c);
int event_add_conn(struct event_base *evb, struct conn *c);
int event_del_conn(struct event_base *evb, struct conn *c);

//等待并执行读写事件
int event_wait(struct event_base *evb, int timeout);
```

## 超时

与libevent的超时设计类似，使用平衡树（rbtree/minheap)维护了链接对应的超时时间，
可以方便地确定event_wait的时间。

不同的是libevent每个event都关联一个超时时间，而twemproxy每个request关联一个超时
时间。

## 定时事件

twemproxy不涉及定时事件。

upredis-proxy设计的定时：beforesleep时进行检测是否达到定时间隔，如果达到则
触发定时事件。

## 信号处理

twemproxy不涉及信号处理。

## 与libevent的主要设计区别

1. 回调设计

libevent每个fd对应一个回调函数；twemproxy整个base对应一个回调函数；

这主要是因为twemproxy将所有的fd都抽象了链接conn对conn读写事件的处理逻辑。
conn读写事件的个性化部分通过注册不同的函数指针覆盖。

libevent作为客户端库，每个fd对应2个回调函数。

2. 超时设计

libevent每个fd对应1/2个超时，而twemproxy每个request对应一个超时。

实现思路是类似的。

## 实现

1. 不同多路复用接口(epoll/kqueue/evport)的选择

通过编译`#ifdef`选择，不同的多路复用接口的`event_base`结构都是不同的。

2.  水平触发与边缘触发

twemproxy采用了边沿触发，边缘触发使用有两点注意：

- fd必须是non-blocking
- read必须读取到read直到EAGAIN

## 关于twemproxy的事件状态

twemproxy的每个fd对应一个conn结构，conn包括前端链接、后端链接、
proxy链接(listen fd)三类。

a)对于proxy conn:

初始状态只有一个proxy (listen)conn，注册了读事件，读事件将accept前端conn。

b)对于前端conn:

twemproxy将对前端conn应注册读事件，并将conn附带在事件私有数据中:


```
      event.events = (uint32_t)(EPOLLIN | EPOLLET);
      event.data.ptr = conn;
      status = epoll_ctl(ep, EPOLL_CTL_MOD, c->sd, &event);
```

事件触发时，调用统一的回调函数并传入私有数据conn。在回调函数中，可以根据
conn对应的read_cb/write_cb执行报文处理。

每种conn对应不同的read_cb/write_cb，负责读取和发送报文；读取到报文之后，
按照redis协议解析得到相应的request/response。

前端链接读取到的request会forward到相应的后端conn，并注册相应的写事件；

c)对于后端conn:

后端写事件触发之后，回调将发送后端报文。

后端conn在创建了链接之后，也会注册写事件（conn为事件私有数据），读事件触发后
，读取到的response会forward到对应request的所在的前端链接，由前端conn发送。

## 处理部分读和部分写

twemproxy和redis一样，都支持客户端pipeline发送请求。客户端可以连续
发送N个请求，然后连续收对应的N个应答。

使用pipeline发送方式，对于1个链接来讲，肯定会存在一个事件循环中读取到
多个request或者部分request的情况。

twemproxy对于部分读的处理策略是将报文读取和报文解析分成两步：

- 报文读取:循环读取该fd，直到EAGAIN
- 报文解析:如果解析到整个报文，则forward到对应的server；如果是半个报文，则把解析的状态保存在当前conn中，下次事件循环继续解析


