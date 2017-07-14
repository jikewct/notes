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

-----------
联调配置中心和配置文件动态生效

配置中心的ip,port先放在hdl_init参数中解析，最后可能会放到共享内存


hdl_init
hdl_reload //如果hdl要支持回滚，可以考虑hdl {ohdl, nhdl}
get_cfg_block();

blen == 0 ??

---------------
配置文件动态生效：
clog_svr: 
对于svr的变更包括增删改

创建+替换：变更瞬间消耗更多的fd，ha状态被重置，但是逻辑更简单易懂;

对比+按需（增加，删除，修改）：变更消耗fd数量减少，ha状态保持，逻辑复杂难把控;

暂时按照创建+替换策略进行。


--------------
方案评审结果

1. 配置中心配置文件指定那些位置是用来hash的（比如说用机构名称作为哈希key，那么
同一家机构的文件会被hash到同一个位置

2. recv时间可以适当优化（比如发送之后才进行接收，间隔多长时间才进行接收，以降低频次）

-----------
1. 增加md5&version变化功能
2. 基本功能测试
4. 系统测试框架

1. 单笔发送
2. tps 1 发送
3. tps 1000 发送

-----------
A) 测试
1. 功能测试
2. 性能测试
3. 单元测试
4. 系统测试

B) 优化
1. clogs_info 非定长
2. \r\n
3. 类似于hashtag功能的设计与开发
4. 优化recv次数，确定技术参数

C）脱敏插件
1. 8583
2. fml
3. xml
4. tlv

------------------------
开发8583脱敏插件

两种方案:

1. hardcode 

由于8583的报文规范是统一的，所以每一个域对应的解析方法和脱敏方法都是已知且固定，
因此可以hardcode, 也不用配置脱敏规则。

1.1 实现

按照8583的报文规范进行编码

1.2 分析

1.2.1 优点

- 实现简单
- 无需配置

1.2.2 缺点

- 没有在8583中规定的域无法处理
- 如果8583的规范更新，clogs需要相应更新


2. 配置

由于8583报文规范会更新，但是使用的数据描述方法基本不变（定长数据，变长数据，TLV等）
因此可以通过配置8583的解析和脱敏规则来应对不同的8583报文规范和不同的脱敏需求。

2.1 实现

2.1.1 脱敏

配置：

14,35,36,47.A1,52,55,61.1,61.4[4-6],61.6.AM[17-165],61.6.NM,63.SM

数据结构：

repconf { id : {range,to} }

算法：

解析时产生事件
通过事件id找到{range,to}
执行替换
    
2.1.2 解析

将8583报文理解为树形结构，8583报文.[2-128域].用法.子域.用法...
解析每一个节点都会产生一个事件，事件id为以上路径。


配置：（暂时不配置，避免解析复杂配置文件；但是在代码中给出模板配置和默认配置）

数据结构：

struct field {
    char *id;           /* 域id */
    parse_t parse;      /* 解析本域的函数, n, var... */
    child_t child;      /* 获取子域id的函数 */
    u_hash_t childs;    /* 可选子域列表 {id : field} */
}


初始化:

8583:
    hdr_8583
    child_8583
    2 => <field>:
        hdr_n(2)
    3 => <field>:
        hdr_def(6)
    4 => <field>:
        hdr_def(12)
    5 => <field>:
        hdr_def(12)
    6 => <field>:
        hdr_def(12)
    7 => <field>:
        hdr_def(10)
    9 => <field>:
        hdr_def(8)
    10 => <field>:
        hdr_def(8)
    11 => <field>:
        hdr_def(6)
    12 => <field>:
        hdr_def(6)
    13 => <field>:
        hdr_def(4)
*   14 => <field>:
        hdr_def(4)
    15 => <field>:
        hdr_def(4)
    16 => <field>:
        hdr_def(4)
    17 => <field>:
        hdr_def(4)
    18 => <field>:
        hdr_def(3)
    22 => <field>:
        hdr_def(3)
    23 => <field>:
        hdr_def(3)
    25 => <field>:
        hdr_def(2)
    26 => <field>:
        hdr_def(2)
    28 => <field>:
        hdr_def(9)
    32 => <field>:
        hdr_n(2)
    33 => <field>:
        hdr_n(2)
*   35 => <field>:
        hdr_n(2)
*   36 => <field>:
        hdr_n(3)
    37 => <field>:
        hdr_def(12)
    38 => <field>:
        hdr_def(6)
    39 => <field>:
        hdr_def(2)
    41 => <field>:
        hdr_def(8)
    42 => <field>:
        hdr_def(15)
    43 => <field>:
        hdr_def(40)
    44 => <field>:
        hdr_n(2)
    45 => <field>:
        hdr_n(2)    :47.A1需要脱敏但是规范中没有说明
*   48 => <field>:
        hdr_n(3)
        child_n(2)
        AA => <field>:
            hdr_left
        BC => <field>:
            hdr_left
        NK => <field>:
            hdr_left
        ...
        AS => <field>: NOTE 并不是自描述的tlv!
            hdr_left
            child_multi(2)
            AA => <field>:
                hdr_n(3)
            IN => <field>:
                hdr_n(3)
            IP => <field>:
                hdr_n(3)
            ...
            CS => <field>:
                hdr_n(30)
    49 => <field>:
        hdr_def(3)
    50 => <field>:
        hdr_def(3)
    51 => <field>:
        hdr_def(3)
*   52 => <field>:
        hdr_def(64b)
    53 => <field>:
        hdr_def(16)
    54 => <field>:      NOTE 为啥100以内的数字需3B？
        hdr_n(3)
*   55 => <field>:      NOTE 格式TLV, V属性为cn, b, an等
        hdr_n(3)
        child_tlv(1-2)
        9F26 => <field>
            hdr_tlv
        ...
        8A => <field>
            hdr_tlv
    57 => <field>:      57域CI用法难道不需要脱敏？
        hdr_n(3)
        child_n(2)
        AB => <field>:
            hdr_left
        IP => <field>:
            hdr_left
        CI => <field>:
            hdr_left
        RP => <field>:
            hdr_left
        AS => <field>:
            hdr_left
            child_tlv
            AB => <field>:
                hdr_tlv
            IP => <field>:
                hdr_tlv
            CI => <field>:
                hdr_tlv
            RP => <field>:
                hdr_tlv
            NA => <field>:
                hdr_tlv
            IA => <field>:
                hdr_tlv
            SE => <field>:
                hdr_tlv
            AR => <field>:
                hdr_tlv
    59 => <field>:
        hdr_n(3)
        child_n(2)
        QL => <field>:
            hdr_left
        QD => <field>:
            hdr_left
        QR => <field>:
            hdr_left
    60 => <field>:
        hdr_n(3)
        child_incr(3)
        1 => <field>:
            hdr_def(4)
        2 => <field>:
            hdr_def(11)
        3 => <field>:
            hdr_def(15)
    61 => <field>:
        hdr_n(3)
        child_incr(6)
*       1 => <field>:
            hdr_def(22)
        2 => <field>:
            hdr_def(1)
        3 => <field>:
            hdr_def(1)
[4-6]   4 => <field>:
            hdr_def(7)
        5 => <field>:
            hdr_def(1)
        6 => <field>:  该域的长度如何确定？必须要表达left语义
            hdr_left
            child_n(2)
            SC => <field>:
                hdr_left
            AR => <field>:
                hdr_left
            SA => <field>:
                hdr_left
            CR => <field>:
                hdr_left
[17-165]    AM => <field>:
                hdr_left
*           NM => <field>:
                hdr_left
    62 => <field>:
        hdr_n(3)
        child_single(2)
        IO => <field>:
            hdr_left
    63 => <field>:
        hdr_n(3)
        child_multi(2)
*       SM => <field>:
            hdr_n(3)
        TK => <field>:  确认TK用法的格式, 而且TK用法应该还有敏感数据吧？
            hdr_n(3)
    70 => <field>:
        hdr_def(3)
    90 => <field>:
        hdr_def(42)
    96 => <field>:
        hdr_def(64b)
    100 => <field>:
        hdr_n(2)
    102 => <field>:
        hdr_n(2)
    103 => <field>:
        hdr_n(2)
    121 => <field>:
        hdr_n(3)
    122 => <field>:
        hdr_n(3)
    123 => <field>:
        hdr_n(3)
    128 => <field>:
        hdr_def(64b)


解析:

PARSE f
    parse() /* 设置pos， len */
    id = child() /* 如果有子域，那么
    if (id) 
        PARSE f->childs[id]
    
    parse_event(f->id);

seriously:

typedef int (*parse_t)(char *p, 
                       int plen,
                       void *parg,
                       char **fld, 
                       int *fldlen);

typedef int (*child_t)(char *p,
                        int plen,
                        void *carg, 
                        char **id,
                        int *idlen);

struct field {
    char *id;           /* 域id */
    parse_t parse;      /* 解析本域的函数, n, var... */
    child_t child;      /* 获取子域id的函数 */
    u_hash_t childs;    /* 可选子域列表 {id : field} */
	void *parg;
	void *carg;
}


int push_path(char *path, char *id, int idlen);
int pop_path(char *path);

int notify_parsed(void *ctx, char *path,
                 char *fld, int fldlen)
{
    if (u_hash_contains(ctx->hash, path)) {
        range = u_hash_lookup(ctx->hash)->range;
        sub(fld, fldlen, range);
    }
}

int parse_8583(char *p, int plen, void *parg,
                   char **fld, int *fldlen)
{
    //跳过hdr，mti，bitmap

    //将bitmap存入state中

    *fld = pn;
    *fldlen = plen - len(hdr+mti+bitmap)

    //TODO 怎么确定max fld
}

int parse_nop(char *p, int plen, void *parg,
                   char **fld, int *fldlen)
{
    *fld = p;
    *fldlen = plen;
}

int _n(char *p, int plen, void *parg,
            char **fld, int *fldlen)
{
    *fld = p;
    fldlen = parg;
}

int parse_var(char *p, int plen, void *parg,
              char **fld, int *fldlen)
{
    int vlen = parg;
    *fldlen = strntoi(p, vlen);
    *fld = p + vlen;
}

int parse_tlv(char *p, int plen, void *parg,
              char **fld, int *fldlen)
{
    int llen;
    if (0x80 & *p) { /* 1字节 */
        *fld = p + 1;
        *fldlen = *p;
    } else {
        llen = 0x80 & *p;
        *fld = p + 1 + llen;
        *fldlen = ntohx(p+1, llen);
    }
}



/*  域2,3,...70 */
int child_8583(char *p, int plen, void *carg, 
               char **id, int *idlen)
{
    //根据当前state, 找到下一个 id

   
}

/* 子域 1,2,...; */
int child_incr(char *p, int plen, void *carg, 
            char **id, int *idlen)
{
    //根据当前state，populate下一个id
    int *cur = carg;
    *cur += 1;
    id = itoa(*cur);
    id_len = strlen(id);
}

/* NM用法，TK用法等 */
int child_n(char *p, int plen, void *carg, 
            char **id, int *idlen)
{
    *idlen = carg;
    *id = p;
}

/* 9F33, 95等 */
int child_tlv(char *p, int plen, void *carg, 
              char **id, int *idlen)
{
    if ( *p & 0x1F == 0x1F) { /* 2字节 */
        *idlen = 2;
        *id = p;
    } else { /* 1 字节 */
        *idlen = 1;
        *id = p;
    }
}

int hdr_n(char **p, int len, void *arg, void **state, char **v, int *vlen)
{
    int *ist = calloc(1, sizeof(int));
    *state = ist;

    *vlen = arg;
    *v = *p;
}

int hdr_var(char **p, int len, void *arg, void **state, char **v, int *vlen)
{
    int *ist = calloc(1, sizeof(int));
    *state = ist;

    int x = arg;
    *v = *p + x;
    vlen = strntoi(*p, x);
}

int hdr_nop(char **p, int len, void *arg, void **state, char **v, int *vlen)
{
    *vlen = len;
    *v = *p;
}


/* 只有一个子域，且子域id长度固定 */
int child_n(char **p, int len, void *arg, 
            void *state, char **id, int *idlen, int *childlen)
{
    if (*state == 0) {
        *idlen = arg;
        *id = *p;
        *p += arg;
        *state = 1;
        *childlen = len - arg; /* 子域长度为
    } else {
        *idlen = 0;
        *id = NULL;
    }
}


hdr目的: 获取val长度，设置state

hdr_8583：消耗报文中的hdr+mti+bitmap
hdr_def: 不消耗报文，8583标准规定（固定）长度
hdr_left: 不消耗报文，父域剩余长度即为本域长度
hdr_n: 消耗固定字节的报文，表示该域长度
hdr_tlv: 消耗tlv中的l，长度按照tlv标准解析

child目的: 获取子域id，调整state

child_8583：不消耗报文，根据8583报文头和当前idx，获取下一个子域id
child_incr：不消耗报文，根据当前id和子域数量限制，获取下一个子域id
child_n: 消耗固定字节，表示子域名称
child_tlv: 消耗tlv中的t，长度按照tlv标准解析

typedef struct {
    int idx;
    void *arg;
} state_t;


/*
 * p        msg ptr
 * left     left length (used to determine if child exist)
 * arg      related arg (max child count, child id length)
 * st       state
 * id       child id
 * idlen    id length
 */
typedef int (*child)(char **p, int left, void *arg, state_t *st, char **id, int *idlen);


/*
 * p        msg ptr
 * left     left length (used to determin field length)
 * arg      related arg (max field count)
 * st       state
 * val      value ptr
 * vlen     value length
 */
typedef int (*hdr)(char **p, int left, void *arg, state_t *st, char **val, int *vlen);


/* 
 * p            msg ptr
 * fc           current field configuration
 * left         left length to parse for parent field
 * path         e.g. "61.1.AM","47.A1"
 * ctx          plugin context
 */
int parse(char **p, int left, fldconf *fc, char* path, void *ctx)
{
    state st = {0, 0, 0};
    char *val, *id = NULL;
    int vlen, idlen, nleft;

    fc->hdr(p, left, fc->harg, &st, &val, &vlen);

    if (fc->child) {
        do {
            nleft = vlen - (*p - val);
            fc->child(p, nleft, fc->carg, &st, &id, &idlen);

            if (id) {
                nleft = vlen - (*p - val);
                push_path(path, id, idlen);
                parse(p, nleft, fc->childs[id], path, ctx);
                pop_path(path);
            }
        } while (id);
    }

    *p = val + vlen;

    notify_parsed(ctx, path, val, vlen)
}

struct ctx {
    field *fldconf8583;
    u_hash_t repconf;
}

void *clogs_rep_plug_create(const char *expr)
{
    /* 根据8583配置文件，初始化ctx->fldconf8583 */
    /* 解析expr，生成脱敏配置 ctx->repconf*/
}

int clogs_rep_plug_sub(void *ctx, char **msg, int *mlen)
{
    char path[MAX];
    char *p = *msg;
    int len = *mlen;

    parse(&p, &len, ctx->fldconf8583, ctx); 
}


2.2 分析

2.2.1 优点

- 解析配置灵活，应对8583报文规范更新和变种,也能配置不同的解析粒度
- 脱敏配置灵活，应对不同的脱敏需求

2.2.2 缺点

- 实现稍复杂
- 配置稍复杂

---------------
1. 评估hardcode&conf之间的工作量差别
2. 获取8583样本报文
3. 分析四大系统之间的8583报文差别，对四大系统整体结构进行了解
4. 分析gfs的做法, 为啥gfs里面会有bcd，asc之类的区分，gfs的架构是怎样的！
5. 退一万步，回头想想以上两个方案真的就只有这两个方案？
6. 明天方案评审：整理8583的域属性和简短说明（先介绍8583报文）
                 再整理四大系统的8583差异（了解四大系统的结构，商户，受理，发卡等）
                 说明n个方案，并作对比
                 自己的意见

-----------------
解析配置文件
1. 通过expr传进来
expr = parse=8583-maps;rep=...


-------------------
gfs对8583的解析

- MTI:8583的MTI有bcd和asc两种不同的编码方式，其中cups使用的是asc，占4字节，xx使用bcd，占2字节
- bitmap: bitmap也有 bcd和asc ？我去
- 其他域：根据配置文件的配置，进行分解

对于clogs的参考意义：
1. 任何域的长度和数据都可能是bcd和asc！
2. gfs的代码貌似比较丑陋啊！


-------------------

对8583解析方案进行优化：
从最终设计和灵活度以及支持包的重组考虑
另外考虑配置的友好度，代码的可维护性

自己编写一个8583库，那么问题都解决了：

parse，foreach sensitive：do set；assemble （如果不需要拷贝，则不拷贝）

是不是要做到配置与数据分离，毕竟大部分情况配置是不变的：

struct u8583 {
    u8583_cfg cfg[1];
    u8583_fld fld[1];
    char *buf;
    int blen;
}

u8583 *u8583_new(const char* conf_fn);

int u8583_parse(u8583 *u, char *msg, int mlen);

int u8583_get(u8583 *u, char *path, char **val, int *vlen);
int u8583_set(u8583 *u, char *path, char *val, int vlen);

int u8583_pack(u8583 *u, char **buf, int *blen);

void u8583_destroy(u8583 *8);

1. set问题， 内存？如果超过了长度？如何生成brandnew? （默认值的问题）
2. 如何解决有些域是可选域, 组合域的问题
3. 如何aggregate

用buf保存dirty域，组合的时候进行拷贝（如果没有dirty，则不拷贝，层层dirty）

配置上如何简化，感觉问题还比较多，因此先暂时搁置，等到需要做解组包组件的时候在考虑。




//TODO 从父节点传递到子节点的信息应该不止nleft，需要考虑其他的信息传递
//     如果我需要修改hdr呢？
//     如果我需要知道hdr呢？
//     能不能不用hdr函数，都看成val, 因为有时候需要修改自主修改hdr
//     需要考虑更加容易理解，因为维护者可能会改变




-------------------------------------
8583 测试日志

疑问
48域                                                :   PA用法没有在规范中说明, AS.OA用法没有说明(20170603-C-14)
59域 明细查询数据                                   ：  数据：'-' 不合规范， AI用法，BI用法没有在规范中说明
60域 自定义域 3个子域（4,11,15，var）至少30字节     :   00000 00103 0000
61域 证件编号 6个子域（22,1,1,7,1，var）至少32字节  ：  000      61.6 RZ用法未定义（20170601-A-11)


bug
1. 对异常报文头处理不正常，导致出现vlen计算错误
2. child_incr的判断错误，导致总是limit少一个


61.6.CU为什么出现该用法？ 58 61 64
原因shi对61.6域的理解不正确，61.6（CUP+用法+数据）

TODO: 根据MAPS的8583规范（处理没有头的8583hdr函数）写插件yml配置，并在201706月以来的报文上测试

--------------------------------------
server 重构
1. 命令行参数
2. memleak
3. 对aio部分进行理解
4. 对整体进行重构



mess like shit:

基本没有对返回值做过检查，日志也很不规范
没有清理工作，有内存泄露
能不能避免全局变量

多线程的信号量问题：signal_ev真的能正常工作？
为什么线程模型是现在的结构？大量的全局变量方便？不可避免？
另外在开源产品中如何使用init new del create destroy free等关键词?我应该如何用？
server在进程基本组成方面比较混乱（没有ctx，instance，option等概念）
另外，为啥我写的代码看起来格式那么难看？？？

如果把全局变量放到ctx或者instance中，便没有那么多全局变量




--------
关于关键词的使用
在pthread中：
pthread_create
pthread_exit
pthread_cacel

pthread_attr_init 设置默认值
pthread_attr_destroy 不释放内存

pthread_mutext_init 设置默认值
pthread_mutext_destroy 不释放内存

综上：pthread认为init/destroy对应，两者均不会申请/释放内存（pthread是比较怪异的一种）

在libevent2中
event_base_new
event_base_new_with_config
event_base_free

event_config_new
event_config_free

综上：libevent认为new与free对应，new 是ctor，free是dtor

在twemproxy中:
conf_create 申请内存
conf_destroy 释放内存

string_init
string_deinit  申请/释放/初始化 member

array_init
array_deinit  申请/释放/初始化 member

conf_server_init
conf_server_deinit 申请/释放/初始化 member

conf_pool_init
conf_pool_deinit 申请/释放/初始化 member

init与deinit是一对， deinit会将member释放, 但是本身并不释放。

conn_init/conn_init
conn_free/conn_get/conn_put

综上：twemproxy认为create/destroy对应，create为ctor，destroy为dtor；init/deinit对应，init&deinit只对member进行操作；


pthread的语义比较奇怪；
准备以后采用类似于面向对象的语义：
new/free分别表示ctor；dtor
init/deinit分别表示初始化和反初始化；

什么情况下init/deinit?
string
array
log
conf_pool
conf_yaml
server
conf_server
conn
msg
mbuf
proxy
server
server_pool
signal
stats_metric
stats_server
用的频次较高，结构简单；如果一旦需要在栈内存或者text内存中出现，则必须有init/deinit

什么情况下new/free?
event_base
conf
array
core_ctx
stats
用的频次很低（基本上都是一个hdl/ctx一个，而且这些数据结构通常比较复杂, 只会在堆内存使用)

什么情况下new/free init/deinit共存？
array
new/free是array的scaffolding,其实我觉得一般情况下不共存，除非两种情况都用的很频繁（类似strcpy，strdup）

cdb-pub, glib:
使用关键词new/free，并且不提供init，deinit；

-----------------
今天的任务：
1. 理清ctx，instance，option
2. 看懂clogs-server（当然要包括aio）
3. 思考重构点（合并结构，整理进程架构为配置动态生效提供可能）
4. 重构代码（包括plugin）
5. 测试重构代码并推送到master，后面的MR必须rebase


节外生枝
如何进行排版
vim-easy-align ga=

1.
一个进程, 一个instance
一个进程运行的时候只会输入一次args，但是可能多次对配置文件进行重载
conf和arg要分开，那么setting呢？
另外进程的 usage和version应该和arg进行比较紧密的联系

信号量，pid, log

真正的进程运行流程：
ctx_new
ctx_loop
core_free

在reload的时候，变更的操作

全局参数(help version demonize test_conf...)，进程参数(pidfile conf_fn log_level  ，配置文件参数

感觉上这个问题比较复杂，需要考虑的方面也比较多（有时候考虑到实现的简便性，没有必要引入这么多概念）
twemproxy reload对ctx中的server_pools做变更；
redis config set做reload
clogs-cfg-center 用 只变更appconfs

结论：
1. 一个进程，一个instance(可省略）
2. 一个instance一个ctx（config-reload就是对ctx进行重建？）

简而言之：
1.处理进程级别的任务（help，version，demonize，verbose等）
2. ctx_new
   ctx_start
   ctx_run
   ctx_stop


进程的启动包括以下：
0. 创建cmdopts
1. 创建instance
2. 设置默认参数（cmdopts, instance_options）
2. 获取命令行参数(cmdopts, instance_options)
3. ctx操作:
   ctx_new
   ctx_start
   ctx_run
   ctx_stop



2. 

总体设计思路: 分成三组线程，对应三个文件；三组线程继承基础线程（提供同步等公共机制）
每组进程都使用全局变量表示当前的线程组信息；

关于save_thd的理解：
io_setup
io_getevents

日切为啥24小时切一次？

io_getevents
aio任务submit之后如何判断已经完成？完成了之后需要做些什么处理
为啥用libevent读取
why create_file_event


大致异步io的处理思路：

io_setup            //创建aio上下文
io_prepare_pwrite   //准备写入（对io_cb结构进行赋值）
io_set_eventfd      //关联eventfd（io任务完成后，通知efd）
io_submit           //提交io任务
...
io_getevents        //获取完成的io任务，释放相应资源


经过以上四个步骤，io任务提交到内核执行；
当内核执行完成之后，内核将通过efd通知完成的io任务数量
之后通过io_getevents来得到完成的io任务，从而释放相应资源。


3. 

命令行
命名
context


------------------
twemproxy中依靠请求异常来感知svr异常，由于clogs svr不回复消息，因此不准备修改ha策略

需求变更：
1. 使用tcp发送消息

A：阻塞发送客户端请求
影响客户端消息发送
耗费的sd数量较多(nsvr+1)

B: 非阻塞发送客户端请求
不影响客户端消息发送
耗费sd数量多（nsvr+1）

阻塞非阻塞之间的差别巨大：
1. 需要保存消息队列（耗费的内存可能较大，考虑直接丢弃）
2. 非阻塞写需要一次些尽量多；



几个需要确认的问题：
1. ha策略还用udp是否可行？(应该是不可行的，因为socket函数指定了协议）
2. 阻塞/非阻塞
阻塞：简单,只需要修改ha；但可能影响app；
非阻塞：几乎不影响app；需要维护消息队列；

-------------------
jemalloc入库
jemalloc怎么编译？入库？cpm引入？

1. 首先jemalloc都是编译出来的je_malloc, je_calloc带前缀的函数
2. clogs使用的时候怎么找到jemalloc的？(通过在EXT_DIR中添加jemalloc找到的）
3. 如果使用cpm，我们应该怎么引入？(直接将jemalloc入库，然后依赖于jemalloc，完美）

cpm入库流程：
1. 向总工室申请jemalloc入库
2. 准备具体的版本等等的材料

先准备编译脚本（有可能是scdong需要准备先搁着）
在准备udp测试相关的材料
我擦泪，主要是测试报告

--------
关于udp丢包的测试：





====================== ====================== ====================== =================
new era (FOCUS)
====================== ====================== ====================== =================

TODO总结：
x 1. clogs_server简单整理: 函数命名整理，命令行整理
x 2. hash_tag功能开发 (由于在大数据上存储，所以没有这个问题）
x 4. 优化recv次数
x 7. 修改log_info
x 3. \r\n

8. 日志回调
6. TCP，TCP，TCP
5. 测试框架

-----------
8. 日志回调

日志回调是进程级别还是hdl级别？
libevent 进程级别, 静态指针log_fn，如果设置了就是用log_fn，否则用stderr;

类似地：clogs中进程级别



关于日志模块的思考：
首先应该分成两种日志模块，进程日志和API日志。

日志概念：
日志级别：debug（可以随便打印），info，warn，error，fatal(都不能随意打印，需要仔细
考究格式和打印时机）
通常我们都会希望显示更加详实的信息，比如说：
[timestamp] [severity] [file] [line] [message]

系统日志：
kill -x 调整日志级别
输出到文件或者stdout

参考系统：
twemproxy：

struct logger {
    char *name;  /* log file name */
    int  level;  /* log level */
    int  fd;     /* log file descriptor */
    int  nerror; /* # log error */
};

#define LOG_EMERG   0   /* system in unusable */
#define LOG_ALERT   1   /* action must be taken immediately */
#define LOG_CRIT    2   /* critical conditions */
#define LOG_ERR     3   /* error conditions */
#define LOG_WARN    4   /* warning conditions */
#define LOG_NOTICE  5   /* normal but significant condition (default) */
#define LOG_INFO    6   /* informational */
#define LOG_DEBUG   7   /* debug messages */
#define LOG_VERB    8   /* verbose messages */
#define LOG_VVERB   9   /* verbose messages on crack */
#define LOG_VVVERB  10  /* verbose messages on ganga */
#define LOG_PVERB   11  /* periodic verbose messages on crack */

static struct logger logger

log_init
log_deinit
log_reopen
log_level_up
log_level_down
log_level_set
log_stacktrace
log_loggable


感觉上twemproxy的实现对于进程日志来说，是比较典范的, 在功能上：
file，line，level等各种功能都有
可以定位到文件

在实现上:
log必须是宏，因为需要使用__FILE__, __LINE__这样的宏定义
没有影响errno
另外logger结构体包含了，level，fd，name等属性

clogs：
clogs完全使用宏定义；功能上缺file,line...
只有全局数据level


redis:
没有提供file，line功能，但是提供了时间戳功能，同时提供了raw 格式功能。
实现上比较精简

memcached:设计比较奇怪！算了不研究


总结：
clogs 目前只是功能比较少，其他的都还行吧，是一个正常的进程log
从实现上来讲，twemproxy是比较具有借鉴意义的。


库日志：

日志回调显示日志
回调或者stdout

参考系统：
libevent:
因为本身库是附着在进程中运行的，因此没有filename，level，fd等等的概念, 只有一个callback。
一般logcb都是进程级别的。

event_errx 其中后缀为x的都是没有打印errno, strerr的

主要思路：
外用的callback：   logcb(int severity, char *msg)
内服的scaffolding：event_err event_warn ... event_debug

upredis-api-c:
与libevent的比较类似


不过从中可以看出upredis-api-c的代码质量应该还可以！

---------------
va_list

只要是在函数声明中使用了 ... 都叫做varaidic function
要获取这个变参:

valist ap;

va_start(ap, pararm);
va_arg(ap, type); //类似于一个迭代器，取得的是下一个va；如果type不匹配，那么错误不可知
va_end(ap);

// c99
va_copy(dst, src);

//另外format可以指定archetype 为printf, scanf, strftime or strfmo, 来让编译器执行类型检查。
//libevent就使用了format, so：使用类型检查！

format(archetype, string-index, first-to-check)

--------------
总结下， log可能涉及的特性：

[common]
__FILE__, __LINE__, __FUNC__, __VA_ARGS__
timestamp
raw
errno, strerr

[进程]
file/stderr
level up/down (kill -x )

[lib]
callback


-------------------

关于测试框架, 需要考虑的问题：

1. 单元测试框架已经是确定的！cmokery做单元测试!
2. 系统测试只是需要shell脚本做一个收集? 


先看看别的项目的解决方案：
redis       tcl
twemproxy   nosetest
jemalloc    自写单元测试框架
cdb-pub     cmokery
mysql       mtr

最好能给出来测试方案和tcp方案：

测试:

单元测试 cmokery
性能测试 cli
五高测试 python

如果直接都用cmokery的话, 缺点在哪里？
五高测试需要做到：
1. 部署系统 拷贝bin，配置文件 (shell最擅长！）
2. 启动系统，关闭系统（setup，teardown）（shell最擅长）
3. 做检查（得到系统内部的信息） （cmokery最擅长）


----------------------
方案：
1. shell + test_clt_d
shell负责准备配置，部署（cfg_server, server)，启动test_clt_d, 停止(cfg_server, server)，添加防火墙规则等。
test_clt_d负责执行从shell中传递进来的一系列指令：

init
send
assert 
assert_log
可以参考upsql-proxy的perl+bin的方案；


2. python <--(socket/udp)--> test_clt_d
python负责准备配置，部署（cfg_server, server)，启动test_clt_d, 停止(cfg_server, server)，添加防火墙规则等。
test_clt_d负责 接受socket传入的命令（init，send, stat）
python负责通过socket接收结果, 比对结果

比较接近的是twemproxy的nosetest方案；


3. python call clogs-client.so
类似于c#的dllimport（将clogs-client中提供的API函数封装为python 函数，并进行直接调用）

简单poc验证可行


方案1 test_clt_d过于复杂，不准备实行
主要对比方案2和方案3

方案2优点：socket通信灵活可靠；托管程序（python）和非托管程序（test_clt_d）分离，不会出现奇怪的坑；
test_clt_d实现比较简单；

方案3优点：不需要test_clt_d；可以更加方便地调用客户端函数；

-------------------
TODO

x 0. 日志格式（file太长了）
x 1. 测试准备（部署，

x 2. 决策使用2,3哪种方案 使用方案3
3. tcp方案
4. clogs-server/config-center pidfile/log to file , host port argument? 


-------------------

我擦泪，修改的多项功能都没有经过测试,现在都要进行重新的测试
1. 报文格式\r\n
2. 优化recv次数


------------
x 1. clt_cli中的日志采用回调函数
x 2. 发现clogs_cfg_server中的内存被覆盖的bug, 并修复
x 3. 发现clogs_proto中有些域可能含有\r\n，导致strtok切割失败的bug，已修复
x 4. 发现clogs_proto中有些域是文本域，但是没有添加\0导致拆分不正常, 已修复
x 5. 法相proto pack reserved的时候没有判断reserved是否为NULL
x 6. 整理联调测试需要的客户端和header以及简单文档

-------------
1. 客户端tcp
2. 整理ha测试案例，集成测试案例

客户端tcp
1. MAPS.ini添加以下配置选项：

# tcp or udp(default)
send_proto = tcp
# support K, M, B(default)
send_buf_size = 1M


a）为什么不在clt.ini中添加，clt.ini与MAPS.ini能否合并？
如果在clt.ini中添加，reload时候需要更新多个机器（使用多个clt.ini)配置，不方便
不能合并，否则更新配置文件需要到多个机器上修改，不方便

2. 几个设计准则：
a）非阻塞发送（不能给app带来延时）
b）当eagain时，缓存消息到buf中
c）为了不对app带来过多的内存消耗，缓存消息有上限（send_buf_size)
d) 如果缓存超过上限，则丢弃数据

因此以上比较重要的缓存管理的设计

设计为一个滚动buffer:


/* 
 * try to copy n byte to rb:
 * if total - used >= n: copy to rb
 * if limit - used < n: can't copy
 * else: try expand rb and copy to rb
 */
int roll_buf_use(roll_buf *rb, char *p, int n);

/* return n byte to rb */
void roll_buf_ret(roll_buf *rb, int n);


