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

