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

/* try recover & isolate */
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



------------------------
Mon May  8 10:13:14 CST 2017
决定采用clt ha 方案
经过思考算法如下：

HA_CHK_GAP    5000 /* 5000ms */

enum ha_chk_state { 
    PONG=0, /* pong received */
    PING,   /* ping sent, waiting for pong */
}

struct svr {
    ...
    struct timeval  next_ha_chk;            /* next ha chk timestamp */
    ha_chk_state_t  ha_chk_state;           /* current ha state: ping or pong */
    int             ha_invalid_cnt;         /* consecutive invalid ha chk count */
    int             isolated                /* isolated or not ? */
}


algo:


## init ##
svr->ha_chk_state = PONG
svr->next_ha_chk = 0;
svr->ha_invalid_cnt = 0;
svr->isolated = 0;

##send msg##

select svr 

if svr->next_ha_chk <= now:
     if svr->ha_chk_state == PING:  /* still waiting for ack */
         ack = drain_ack_nonblock
         if ack_invalid(ack):
             svr->invalid_cnt ++
             try_isolate_svr(svr)

     send ping_msg(svr->ping_id)    /* send ping msg */
     svr->ping_id += 2
     svr->next_ha_chk = now + HA_CHK_GAP
     svr->ha_chk_state = PING

else:
    if svr->ha_chk_state == PING:   /* waiting for ack */
        ack = drain_ack_nonblock
        if ack_valid(ack):
            svr->ha_chk_state = PONG
            try_recover_svr(svr)

    else /* got valid ack with in HA_CHK_GAP, waiting for next ha_chk */           



----------
编码

1. 如何防止管理员修改系统时间
参考memcache
使用clock_gettime能防止，但是这个函数在AIX有么？
先用timeval & gettimeofday

2. ha时：如果svr isolated 是否需要重新选择？
不重新选择
a. 阻塞问题 b.复杂度 TODO

3. 发送，接收ack的协议 done

4. ketama与svr的review（autoeject怎么实现?）done

5. 由于pong不能混在一起，所以必须要让clt中的每个svr包含一个sd，这样下来可能会很多sd！ done


---------
ha

1. review, 从一个更高的角度看下
2. 调试 & 测试
a. ping pong
b. 2->1

测试案例
a. 2->1->0->1->2


-----------
cli
参考redis-cli/redis-benchmark提供压测功能
基本功能：
clogs-benchmark -n 1000000 --tps 10000 --load-balance 127.0.0.1:6000,127.0.0.1:6001 --mlen 1024 
之后能统计到实际发送的tps和发送的总量


调研redis-cli/benchmark的使用、设计、实现

redis-cli

使用：
Usage: redis-cli [OPTIONS] [cmd [arg [arg ...]]]
-h <hostname>      Server hostname (default: 127.0.0.1).
-p <port>          Server port (default: 6379).
-s <socket>        Server socket (overrides hostname and port).
-a <password>      Password to use when connecting to the server.
-r <repeat>        Execute specified command N times.
-i <interval>      When -r is used, waits <interval> seconds per command.  It is possible to specify sub-second times like -i 0.1.
-n <db>            Database number.
-x                 Read last argument from STDIN.
-d <delimiter>     Multi-bulk delimiter in for raw formatting (default: \n).
-c                 Enable cluster mode (follow -ASK and -MOVED redirections).
--raw              Use raw formatting for replies (default when STDOUT is not a tty).
--no-raw           Force formatted output even when STDOUT is not a tty.
--csv              Output in CSV format.
--stat             Print rolling stats about server: mem, clients, ...
--latency          Enter a special mode continuously sampling latency.
--latency-history  Like --latency but tracking latency changes over time.  Default time interval is 15 sec. Change it using -i.
--latency-dist     Shows latency as a spectrum, requires xterm 256 colors.  Default time interval is 1 sec. Change it using -i.
--lru-test <keys>  Simulate a cache workload with an 80-20 distribution.
--slave            Simulate a slave showing commands received from the master.
--rdb <filename>   Transfer an RDB dump from remote server to local file.
--pipe             Transfer raw Redis protocol from stdin to server.
--pipe-timeout <n> In --pipe mode, abort with error if after sending all data.
no reply is received within <n> seconds.
Default timeout: 30. Use 0 to wait forever.
--bigkeys          Sample Redis keys looking for big keys.
--scan             List all keys using the SCAN command.
--pattern <pat>    Useful with --scan to specify a SCAN pattern.
--intrinsic-latency <sec> Run a test to measure intrinsic system latency.
The test will run for the specified amount of seconds.
--eval <file>      Send an EVAL command using the Lua script at <file>.
--help             Output this help and exit.
--version          Output version and exit.

Examples:
cat /etc/passwd | redis-cli -x set mypasswd
redis-cli get mypasswd
redis-cli -r 100 lpush mylist x
redis-cli -r 100 -i 1 info | grep used_memory_human:
redis-cli --eval myscript.lua key1 key2 , arg1 arg2 arg3
redis-cli --scan --pattern '*:12345*'

理解：
1. redis-cli要么采用interactive mode，要么采用batch-mode
2. 由于客户端有load-balance 和 ha等复杂功能，不能直接采用-h -s 等参数指定，直接采用 -c <conf> 指定配置
3. batch-mode 只要stdin不是tty 那么就是batchmode，该情况fgets读取，否则linoise读取.
4. 如果在命令行中指定了msg，那么也不会进入到interactive mode中

Usage:
clt-cli -c <conf> [-r <repeat>] [-i <interval>] [clogs msg(sys_id msg_type filename msg)]
        --help
        --version

-c <conf>       config file
-r <repeat>     send clogs msg N times
-i <interval>   when -r is used, waits <interval> seconds per command.
                It's possible to specify a sub-second time like -i 0.1.

--help          print this help and exit.
--version       print version and exit.

Examples:
cat test-maps-kv | clt-cli -c /path/to/conf
clt-cli -c /path/to/conf MAPS kv maps.kv hello=world&foo=bar&k=v
clt-cli -c /path/to/conf -r 100 -i 0.1 MAPS kv maps.kv hello=world


理解：
1. 同cli一样，没有-h，-p参数，增加-c参数
2. 需要-c <clients> 指定客户端hdl数量
3. 不需要从文件中输入消息，能够自动产生随机消息
4. 

影响clogs性能的关键参数
-l hdl数量
-c svr
-f 文件数量
-t 消息类型
-d 消息长度

-n 总消息数量
一定要指定tps！要不然肯定出现数据udp buffer满，报文大量丢失
通过何种方式指定？？ sleep ??

实时输出tps数据，最后在统计平均值

Usage: redis-benchmark [-h <host>] [-p <port>] [-c <clients>] [-n <requests]> [-k <boolean>]

    -h <hostname>      Server hostname (default 127.0.0.1)
    -p <port>          Server port (default 6379)
    -s <socket>        Server socket (overrides host and port)
    -a <password>      Password for Redis Auth
    -c <clients>       Number of parallel connections (default 50)
    -n <requests>      Total number of requests (default 100000)
    -d <size>          Data size of SET/GET value in bytes (default 2)
    -dbnum <db>        SELECT the specified db number (default 0)
    -k <boolean>       1=keep alive 0=reconnect (default 1)
    -r <keyspacelen>   Use random keys for SET/GET/INCR, random values for SADD
    Using this option the benchmark will expand the string __rand_int__
    inside an argument with a 12 digits number in the specified range
    from 0 to keyspacelen-1. The substitution changes every time a command
    is executed. Default tests use this to hit random keys in the
    specified range.
    -P <numreq>        Pipeline <numreq> requests. Default 1 (no pipeline).
    -q                 Quiet. Just show query/sec values
    --csv              Output in CSV format
    -l                 Loop. Run the tests forever
    -t <tests>         Only run the comma separated list of tests. The test
    names are the same as the ones produced as output.
    -I                 Idle mode. Just open N idle connections and wait.

    Examples:

    Run the benchmark with the default configuration against 127.0.0.1:6379:
    $ redis-benchmark

    Use 20 parallel clients, for a total of 100k requests, against 192.168.1.1:
    $ redis-benchmark -h 192.168.1.1 -p 6379 -n 100000 -c 20

    Fill 127.0.0.1:6379 with about 1 million keys only using the SET test:
    $ redis-benchmark -t set -n 1000000 -r 100000000

    Benchmark 127.0.0.1:6379 for a few commands producing CSV output:
    $ redis-benchmark -t ping,set,get -n 100000 --csv

    Benchmark a specific command line:
    $ redis-benchmark -r 10000 -n 10000 eval 'return redis.call("ping")' 0

    Fill a list with 10000 random elements:
    $ redis-benchmark -r 10000 -n 10000 lpush mylist __rand_int__

    On user specified command lines __rand_int__ is replaced with a random integer
    with a range of values selected by the -r option.


设计clogs-benchmark
为什么在cli之后还需要一个benchmark工具，能不能合并到一起？
1. 定位不同，cli主要回归测试，benchmark性能测试
2. cli需要输入消息，benchmark自动产生随机消息
3. cli只有一个hdl，benchmark多个hdl
4. cli有iteractive mode，benchmark不需要

？？能否用cli的batchmode替代benchmark？
不好！

所以需要benchmark

Usage:
clogs-bench -c <conf> [-x <hdl>] [-f <nfile>] [-t <msg_type>] [-d <msg_len>] [-z <tps>]
            --help
            --version

-c <conf>       client config
-x <hdl>        # client handle
-f <nfile>      # file per handle
-t <msg_type>   msg type
-d <msg_len>    message length
-z <tps>        message sending tps




---------------
设计方案
0. 协议
   clogs报文(报文格式, udp)
   ping报文(报文格式）

1. 客户端
   概要设计（handle, 数据结构, 报文组装方式和內存管理）
   配置文件(示例，解析，動態生效） 
   ha ha算法，ping报文, 非阻塞, ha与load-balance的配合
   load-balance ketama一致性哈希，按照文件名进行哈希

2. 服务端
   内存管理（內存示意圖）
   脱敏插件系统（插件系统的设计框架）

3. 测试工具
   clogs-cli batch-mode, interactive-mode, 性能测试
   clogs-bench bench工具(模拟多客户端）
