---------
clogs
- 1. 解决pipe，diff, terminal问题: 通过isatty能判断当前的stdin是否为tty，这样就可以对tty和非tty有不同的读取方法，但这个已经被linenoise做掉了
对于log的控制，不能因为out被重定向了就不输出更加详细的信息，应该通过loglevel控制
顺带调研，log的一般做法（proxy，redis，mc）

3. 编辑器原理,终端原理思考
2. 客户端的设计与思考

Mon Apr 24 13:54:38 CST 2017
--------------------
对客户端的思考：

不使用线程的概念，使用ctx概念

暂时先不仔细考虑高可用

API设计如下：

    clogs_ctx_t *clogs_init();
    int u_clog_send(clog_info_t *clog_info, char *msg, int len);
    void clogs_destroy(clogs_ctx_t *ctx);

    typedef void (*clogs_log_cb_t)(int severity, const char *msg);
    void clogs_set_log_callback(clrs_log_cb_t cb);
    
    define MAX_SERV  4

    typedef struct clogs_context {
        time_t shm_up_time;          /*共享内存更新时间戳*/
        int    cfg_chk_period;       /*配置文件更新检测时间间隔*/
        int    server_cnt;            /*服务器个数*/
        server_inf server[MAX_SERV];  /*主服务器配置*/
        server_inf server_bak;        /*备服务器配置*/
        char   server_flag;           /*当前使用的是主还是备服务器*/
        time_t last_cfg_chk;          /*上次配置文件更新检测时间*/
        time_t last_ha_chk;           /*上次服务器状态检测时间*/
    } clogs_context_t;



--------------------------
接下来的工作按照
a. 类似服务端，写一个类似的cli
0. 读取配置文件，并通过, 整理各块的内容
1. 调研负载均衡的实现方式？(twemproxy, codis？负载均衡及hash策略）

负载均衡=>高可用的方向
负载均衡：
1. 文件要尽量放在同一server
2. 因为要实现服务发现，配置文件解析先不做

高可用：
1. 暂定按照线程级别做
2. 需要做探测报文的设计，解析，回复，计数等策略


接下来还可以分析落盘和服务端的配置文件解析等细化工作



--------------------------------
0. 调研 extern on function的意义（其实除了提醒human，对于编译器没啥意义）
1. 调研 libaio 和 kernel aio关系，甄别到centos和suse上的man文档都有误，并找到正确的man文档
2. 分析为啥 core, 因为我的目录啥的不对，先pull
3. 整理cmake，生成一个pub的lib
4. 做一个类似服务端的cli
6. 负载均衡和一致性哈希的调研

首先一致性哈希的解决的就是
增删节点也要保证哈希所在的节点不变

采用了一致性哈希算法的project
twemproxy
libmemcached
lvs(章文嵩，阿里，滴滴，开源）
ngix
haproxy

最好的材料就是twemproxy，重新理解twemproxy的hash算法，并应用到clogs中来。




