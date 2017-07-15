- general idea

```
#define EVLIST_TIMEOUT	0x01
#define EVLIST_INSERTED	0x02
#define EVLIST_SIGNAL	0x04
#define EVLIST_ACTIVE	0x08
#define EVLIST_INTERNAL	0x10
#define EVLIST_INIT	0x80
```

共有INSERTED, TIMEOUT, ACTIVE三种队列

                + - - - - -  - +
                |  EVLIST_INIT |
                + - - - - -  - +
                   event_add
+--------------+                +---------------+
|EVLIST_TIMEOUT|                |EVLIST_INSERTED|
+--------------+                +---------------+
   (+timeout)                     (+read/write)
                +--------------+
                | EVLIST_ACTIVE|
                +--------------+

                + - - - - -  - +
                | EVLIST_SIGNAL|
                + - - - - -  - +
                    (+signal)



ev_flags总是和当前事件在哪些队列同步

> 操作

初始化： EVLIST_INIT, 不添加到任何队列
添加：添加到INSERTED, TIMEOUT(有必要的话）
删除：从TIMEOUT,INSERTED,ACTIVE中删除

> 事件

事件处理的顺序是：先激活读写事件，再激活超时, 最后统一执行激活的事件对应的cb

信号量：dispatch中激活事件
读写事件： dispatch中激活事件
超时： loop中激活事件

问题：
event_set(ev, fd, EV_READ|EV_WRITE|EV_SIGNAL|EV_TIMEOUT|EV_PERSIST, cb1, arg1);
event_add(ev, &tv1);
以上设置恰好在同一个dispatch循环中，同时出现了读/写/超时三种事件，那么
cb1会被执行几次？在出现读/写事件时执行几次？出现超时执行几次？
> set时READ/WRITE; tv1不为null;  因此ev被添加到EVLIST_INSERTED, EVLIST_TIMEOUT
> EV_SIGNAL中的fd表示signo，所以不能混杂在一起指定
> 如果同时发生了读写超时三种事件，那么ev会被激活三次，EVLIST_ACTIVE中会被合并，因而
只有EVLIST_ACTIVE中只有一个ev事件，process时，cb1也就只会被调用1次；

event_set(ev, fd, EV_READ|EV_PERSIST, cb, arg);
event_add(ev, &tv);
persist同时，设置timeout会出现什么结果？ 
> persist只是说处理完事件之后，我们不用手动添加到loop中
> timeout的意思是，过了timeout之后，触发一次cb，然后改事件就被删除了。
> 所以PERSIST & TIMEOUT的意思是： TIMEOUT之前触发事件不用重新add，timeout之后event被del。

- pending?initilized?active?

    initialized: after event_set
    pending: check if event added ?
    active: 内部函数，用于激活事件

- evtimer vs timeout

没有区别, 代码是一样的。

- libevent signal 机制

sig1 \                / ev1_0->ev1_1->...ev1_m
sig2  |   +------+   |  ev2_0->ev2_1->...ev2_m
sig3  |>  | pipe |  >|  ev2_0->ev3_1->...ev3_m
...   |   +------+   |  ...
sign /                \ evn_0->evn_1->...evn_m


event_base {
    sig: evsigal_info {
        ev_signalpair[2]
        ev_signal: event => 
        evsigevents[]: event_list

初始化：
event_base_new
    base->evsel->init
        evsignal_init
            evutil_socketpair
            event_set(ev_signal, ev_signalpair[1], READ|PERSIST,evsignal_cb, ev_signal)
                evsignal_cb
                    recv 1 bit and nothing more
            
添加:
event_set(ev, signo, EV_SIGNAL, cb, arg);
event_add(ev, &tv)
    evsel->add
        evsignal_add
            sigaction(signo, evsignal_handler, osh)
                evsignal_handler
                    evsignal_base->sigevents[signo]++
                    send(evsignal_base->ev_signalpair[0], "a", 1, 0);


触发：
eventbase_loop
    evsel->dispatch
        evsignal_process
            event_active(sig->evsigevents[signo]...)

总结：
1. 每个信号对应一个sigaction，sigaction都添加evsignal_handler（记录信号量，通知epoll收到信号量，i.e. send）
2. pipe接收到信号触发的数据之后，通知epoll可读
3. epoll收到可读（或者INTR）之后，激活信号量对应的事件列表
4. 事件循环处理被激活事件

- http
客户端使用：
evhttp_connection_new（创建链接）
evhttp_request_new（创建请求）
evhttp_add_header(构造请求头部）
evhttp_make_request(请求）

event_dispatch(分发）

服务端使用：
evhttp_new(创建服务器）
evhttp_bindsocket(绑定端口）
evhttp_set_cb(对每个uri设置cb）

event_dispatch(分发）

GET,POST
ARGUMENT in uri
uri encode/decode
html escape
session/cookie
close connection


- dns
- bufferedevent & evbuffer & tag

