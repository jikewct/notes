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


---------------------------------------------------
Tue Apr 18 15:33:26 CST 2017

发送信息->接收->解包替换->落盘

0. 规划两个文件, 用于clogs通信报文的组包和解包
clogs_comm.h 

    struct comm_log_info {
        char sys_id[4+1];     /* 子系统代码*/
        char msg_type[4+1];   /* 报文类型:8583\XML\TLV等:在一个子系统唯一*/
        char file_name[16+1]; /* 日志文件名字 */
        int  head_len;        /* 报文头长度:每个系统自己添加的报文头长度*/
        char reserved[80];    /* 保留字段*/
    }

    
    /*
     *   (客户端模块使用）
     *   将msg和log_info组包形成clogs报文
     *   报文结果放入buffer，避免在pack函数中malloc
     *   返回 buffer 中的报文大小，如果出错返回-1
     *   
     */
    int clogs_comm_pack(comm_log_info_t *log_info, 
                        char *msg, 
                        int len, 
                        char *buffer,
                        int size);
    /*
     *  （服务器模块使用）
     *  将clogs报文解包为log_info和报文主体
     *  报文主体以offset的形式返回
     */
    int clogs_comm_unpack(comm_log_info_t *log_info, char *msg, int len);



    #define CLOGS_MSG_HEAD      0
    #define CLOGS_MSG_TAIL      16
    /* clogs 报文 */
    struct clogs_msg { 
        comm_log_info_t *log_info;      /* ?? */
        char            *buf;           /* 报文存放的buffer */
        int              size;          /* buff size */
        int              offset;        /* 报文体相对buf的偏移 */
        int              len;           /* 报文主体大小 */
        int              seq;           /* 报文序号 */
    }

    #define CLOGS_TO_MSG(clogs_msg) do { clogs_msg->buf + CLOGS_MSG_HEAD + clogs->offset; }while(0)
    #define CLOGS_MSG_SIZE

clogs_comm.c 
    对应的实现

1a. 实现server端/clogs_cli/clogs_send(int sd, comm_log_info_t *log_info, char *msg, int len); 向sd发送clogs报文
1b. 实现server端/clogs_cli/main; 逐行读取输入并发送；帮助命令；配置log_info，server端口等

2. 实现server端/clogs_replace_thread/do_replace_task

3. 一个消息落一行


关于组包解包的思考：
暂定组包方式如下：
+---------------------------------------------------------------------------------------------+-------------------------------+
|sys_id(cstring)｜msg_type(cstring)| filename(cstring)| head_len(cstring) | reserverd(cstring)| msg_len(cstring)| msg(binary) |
+---------------------------------------------------------------------------------------------+-------------------------------+
|        <--                comm_log_info                       -->                           |     <--     msg      -->      |


TODO
1. 考虑使用摘要减小开销，保持高效率（粗略思考下来，涉及到的地方较多，暂且搁置）
2. 关于落盘的思考（思考->调研syslog，apache等对落盘的处理方式）
3. 关于编辑器linoise的调研，理解，使用和迁移到clogs_cli



--------------------------------

串联 接收->脱敏->落盘

1. 任务, clogs_comm, 



--------------------------------

关于libaio
libaio 确实是对于linux kernel系统调用的简单封装
/usr/include/linux/aio_abi.h 是linux对于io_submit,io_destroy等系统调用的实现代码
对于linux的系统调用我们只能通过中断去调用：设置好栈（参数，中断向量等）和寄存器（保存现场，设置新现场等）之后，使用int 80指令进行调用
所以说要使用kernel aio，需要包含libaio.h，使用libaio.h中的声明进行调用；
libaio的实现在~/tmp/libaio中，相关的说明文档也在man文件夹中
项目主页：http://lse.sourceforge.net/io/aio.html（被墙）
centos的manpage描述的是aio-abi.h的内容，不是libaio！ suse manpage 描述的也不是libaio,也不是aio-abi.h的内容

libaio.h typedef struct io_context *io_context_t
linux/aio_abi.h typedef _kernel_ulong_t aio_context_t 

综上所述：使用libaio的话需要参考源代码文件夹下的man文档
man文档的转换方法为 nroff -man io_submit.1 | less -r




-------------------
Thu Apr 27 13:40:34 CST 2017
关于配置的思考

因为服务端和客户端都需要考虑配置文件动态生效功能，所以配置中心不可少

配置中心的功能
1. 发现服务
2. 注册服务？
3. 统一管理
4. 配置变更
5. moved to



配置中心：
1. 每个子系统一套统一的配置文件
2.通过 reload sub_sys client 命令更新配置
3.不备份/双活（服务停止后客户端服务端无法更新配置, 重新拉起即可）
4.client 配置文件由基本配置 拼接 svrs 构成
5.svr启动之后向配置中心注册服务(心跳报文）


客户端:
    get version sub_sys + client;
    get config sub_sys + client; //配置文件作为最小粒度!

    生效: 直接修改hdl

服务端：
    get version sub_sys + server;
    get config  sub_sys + server;
    post status sub_sys + server;

    生效：
        重启？
        stopflag -> 线程join -> respawn threads

        spawn threads -> stopflag -> join -> switch context


另一种高可用方案：
    svr定期向配置中心发送心跳报文，配置中心对svrs的健康状态进行管理（一旦svrs状态变更，则更新客户端配置文件）
    clt定期向配置中心获取配置文件version，如果version更新，则更新配置

目前的高可用方案：
    clt向svr发送探测报文，并且在其中做隔离与恢复。

两种方案的对比：
1. 由于多了配置中心，可以固定服务端口，收取心跳报文，可以将客户端的高可用转移到配置中心进行实现
2. 配置中心的的高可用就不用考虑线程级别，进程级别，机器级别，可以直接坐到分布式的统一
3. 配置中心可以在linux部署，不受限与AIX等跨平台要求

4. 配置中心的复杂度更高，需要承受的tps更高（不过预估总量还是很少）


总结：
   无论如何实现，svr & clt 都先在配置文件的情况下调试通过（暂不考虑高可用）
   首先要确定配置选项和配置文件
   再读取配置文件
   再配置文件reload
   在高可用

-------------------
具体任务
1. 示例svr配置文件 & clt配置文件
2. svr 配置文件解析
3. clt 配置文件解析
4. 高可用讨论

------------------
关于clogs udp线程的理解：
> 解析服务器描述字符串
> 对每个listen：创建svr -> 创建线程-> 设置读事件 -> 开启线程


问题
1. 为啥udp不需要listen?
udp 就是不需要listen, bind之后，就可以recv和recvfrom了。
能不能read，应该是可以的

不能只听一家之言，看看twemproxy怎么设计的, 

    struct server {
        uint32_t           idx;           /* server index */
        struct server_pool *owner;        /* owner pool */

        struct string      pname;         /* hostname:port:weight (ref in conf_server) */
        struct string      name;          /* hostname:port or [name] (ref in conf_server) */
        struct string      addrstr;       /* hostname (ref in conf_server) */
        uint16_t           port;          /* port */
        uint32_t           weight;        /* weight */
        struct sockinfo    info;          /* server socket info */

        uint32_t           ns_conn_q;     /* # server connection */
        struct conn_tqh    s_conn_q;      /* server connection q */

        int64_t            next_retry;    /* next retry time in usec */
        uint32_t           failure_count; /* # consecutive failures */
    };


so,如何设计客户端的client
1. parse 差不多，但是需要一个name，用于ketama，当机器ip更换了之后，可以通过名字找到服务器

typdef struct clogs_one_svr {
    uint32_t        idx;
    clogs_hdl_t     *owner;
    char            name[32];       /* hostname:port or [name] */
    uint16_t        port;           /* port */
    char            addrstr;        /* hostname */
    uint32_t        weight;         /* weight */

    struct sockaddr_in  sa;         /* sa from */
} clogs_one_svr_t;

typdef struct clogs_svr {
    int          nsvr;
    clogs_svr_t *svr;      /* array of clogs_svr_t */
} clogs_svr_t;


----------------------------
评估当前的load-balance机制
1. 负载均衡的粒度到底应该是哪个？消息？文件？
2. 思考满足 指定 + hash 的方案
3. review load-balance 实现

思考高可用和配置中心的实现
1. 


-------------
看看网络编程的书！
浏览发现unix的书可能还不如man-page和谷歌来得快，系统性的话，也不一定有seealso之类的来的好！
abandon

-------------
clogs的高可用策略
如果按照luqiang策略实现：
>>>>>>>
clt:

/* try recover & islate */
if now > last_ping + T
    pong_id = recv
    if (pong_id == ping_id + 1) //valid ack
        if svr down 
            up svr
            update continuum
            NACK = 0
    else    //not valid ack (EWOULD_BLOCK, pong_id < ping_id)
        NACK++
        if NACK > X && svr up
            down svr
            update continum

    ping_id += 2
    ping(ping_idd)

send msg

<<<<<<<<<
svr: 

while(1):
    recv msg
    if msg is ping:
        send ping++;
    else
        rep & save

----------------
clogs的配置中心策略

if now > last_cfg_check + T //超时重传
    send get cfg version
    state = getting_cfg_version
    last_cfg_check = now

switch state:

init:
    pass

getting_cfg_version:
    DRAIN cfg version

    if (version > hdl.version)
        send get cfg
        state = getting_cfg
    else if (version == hdl.version)
        state = init
    else if (version < hdl.version)
        //delayed version ack
    else //error
        pass

getting_cfg:
    recv cfg

    if cfg valid:
        reload cfg
        state = init
    else //error 
        pass

default:
    pass
