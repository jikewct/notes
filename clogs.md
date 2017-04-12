save_thread: 
1. 为什么每个save线程有一个event_base
2. 为什么需要wait_thread_ok ? pthread_create之后线程并没有创建？
3. 为啥在任务队列使用mutex而不使用rwlock？
4. save_thread: 57 bug ?
    save_thd = calloc(1, sizeof(save_thd));
5. 为啥在set_thread需要fd0 & fd1 同时设置cb？
(我的理解是：fd0由replace_thd写入，因而只需要检测fd1的读事件）


一些想法：

wthds管理写盘

wthds_init(cfg) //创建线程组，初始化...
wthds_save(sthd, msg, len) //接受写入请求 MT-safe( ths[hash(filename)].enque(msg, len) & notify 
wthds_destroy(sthd) 

struct wthds {
    evb;
    q_lock;
    q_task;
    nthds;
    wthd *thds;
}

类似地：
sthds 管理脱敏

sthds_init(cfg)
sthds_sub(rthd, msg, len) //接受脱敏请求 MT-safe( ths[index++ %nths].enque(msg, len) & notify
sthds_destroy(rthd)

struct sthds {
    evb;
    index;
    q_lock;
    q_task;
    nthds;
    wthd *thds;
}

rthds 管理读取

rthds_init(cfg)
rthds_recv(uthd, msg, len) //接受脱敏请求 MT-safe
rthds_destroy(uthd)

struct rthds {
    evb;
    index;
    q_lock;
    q_task;
    nthds;
    wthd *thds;
}


----------------------------------------------------

如果仅支持udp协议，使用libevent的必要性在哪里？
1. udp socket无连接，只有一个fd，也就失去了IO复用的意义？



---------------------------------------------------
clogs_cli: 向clogs_svr发送消息，输入为：sub_sys msg_type msg

问题：
1.  报文格式

