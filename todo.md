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

---------------------------------------------------------

关于一致性哈希算法：

原理的说明：https://www.codeproject.com/Articles/56138/Consistent-hashing

总结：
1. 解决添加删除服务器，或者服务器故障时，尽量少的缓存失效
2. 解决思路是：在0-2^32-1连续的空间划分并分配各svr；通过哈希将映射到对应的svr；

对于twemproxy中的ketama的分析
ketama_hash： 4种对齐方式，4种hash值，用到了md5_signature生成15字节的hash摘要；
ketama_item_cmp: 按照hash值进行continuum的排序
ketama_update: 更新生成ketama分布的continuum

ketama_update:
0. 每个svr对应40次hash，每个hash对应4个点，共160个点
1. 统计nlive_svr, total_weight
2. nlive_svr > nserver_continuum: 重新分配 (nlive_svr + 10) * 160个点
3. 对每个svr: 点数量为 [weight / total_weight * 160 / 4 * nlive_svr] * 4
              对svr所属点赋值hash，svr_index
4. 按照hash对continuum进行排序

ketama_dispatch: 二分法找到对应hash的svr_index


关于应用到clogs的思考:

在算法上：
1. 首先不需要区分是否auto_eject_host, 因为我们不希望日志数据丢失，所以肯定是auto_eject_host
2. 如果hdl发现svr失效/恢复，那么执行ketama_update
3. 如果hdl发现svr配置更新，那么执行ketama_update

在实现上:
twemproxy的ketama是紧耦合的，需要用到
1. 统计nlive_svr
2. 统计nsvr
3. 需要svr对应的weight
4. 另外需要对continuum排序

----
调研下有没有独立性更好的consistent hashing
github上star数量最高的ketama也是一个设计比较奇怪的库，使用了shm，读取了配置文件，所以还是自己设计比较靠谱

关于ketama的设计
0. 参考twemproxy ketama
1. 只需要修改ketama_update接口

struct svr_info {
    char *name;
    ...
}

struct continuum {
    int index;
    int value;
}

int ketama_update(svr_info *svr, int nsvr, continuum **ct, int *nct);

svr:数组
continuum:数组

-----
关于md5的理解

二手资料
md5:message digest 5th
md5是一种摘要算法，信息量没有源数据多，因此必然会出现碰撞（两个不同的消息，摘要的值相同）,碰撞概率为1/2^256,概率极其小
另外md5具有两个相差较小的信息，摘要值相差很多的特性

MD5: 速度最快，同时生成的哈希值最短(16 字节)。两个文件的哈希值意外发生碰撞的概率大约是: 1.47 * 10 -29。
SHA1: 其速度一般比MD5慢20％，所生成的哈希值也比MD5的要长一点（20字节）。两个文件的哈希值发生意外碰撞的概率大约是：1*10-45。
SHA256：它的速度是最慢的，通常比MD5慢60%，同时它生成的哈希值也是最长的（32字节）。两个文件的哈希值发生意外碰撞的概率大约是：4.3*10-60。

在不考虑恶意攻击的情况下，摘要值不需要考虑碰撞

MD5         :string=>16byte signature
SHA1        :string=>20byte signature
SHA256      :string=>32byte signature

----
方案复测

概要
1. 首先/var/log/messge是否开启了持久化，持久化策略是啥样?最大文件？最长时间？只保留boot？与journald的区别
> 从manpage看: 能设置最大文件
> 从doc看不出来啥
> 从分析来看:
    默认开启了持久化
    不是只记录一天的日志
    boot 日志记录到了boot.log
    测试限制是否为最大文件时，发现imjournal 有rate-limiting功能，默认为：
        $ModLoad imjournal
        $imjournalRatelimitInterval 600 #600s之内，最多20000条数据被记录
        $imjournalRatelimitBurst 20000
    另外rsyslog会限制每条消息最长1k，所以对于rsyslog而言，不会出现大量的流量
> 区别 systemd-journald的消息包括了syslog中的日志，还包括系统服务的stdout以及stderr输出, audit以及通过API打印的日志


2. journald的持久化策略：是否开启？最大文件？最长时间？只保留boot?为啥还需要一个journald和相应的文件
> 从manpage分析：
   默认不开启持久化, 通过创建/run/log/journal/文件夹可以持久化文件,并且kill -sigusr1 <pid> /run/log/journal/中的文件将罗盘
        或者通过配置文件中的Storage域控制
   流量控制 1000 messages in 30s
   RateLimitInterval=, RateLimitBurst=

   日志滚动策略：通常是通过日志大小控制，也可以通过日志文件时间控制


细节：
1. rsyslog & journald如何实现从kernel ring buffer中捞日志？


性能：
1. 开启了日志持久化之后对于io的影响大约为多少？
如果写入大量的日志，那么会出现结果


--------------------------
Fri Apr 28 10:06:40 CST 2017

1. review sub_sys sys_id两个相同概念的不同名称
    使用sys_id，更加明确


2. review msg_type的不同组包方式(MAPS.1 MAP.MAPS.1)
    组成的时候按照, 为了兼容单个svr进程能够接入多个子系统（不建议的使用方式，但兼容），组合sys_id + msg_type区分消息类型

3. review sys_id 是否需要在clogs_info中出现, 或者在init时候指定
    
4. 仍然有一些_t的使用不规范

关于架构的一些思考
svr进程，一个子系统（一个子系统多个svr进程），一个listen，一个udp线程，一组rep线程，一组save线程

目前的话先兼容原设计，每次通信将sys_id组包，解包


------------------
添加client load-balance功能

1. 从配置文件中读取配置（balance，cfg_chk_interval)
2. 结合ketama hashkit进行一致性哈希和load-balance


虽然说可以让一个客户端hdl支持多个sys_id，但是太傻逼，所以一个hdl只能向一个sys_id发送信息

so. u_clog_init(const char *ini)
    u_clog_send(hdl, log_info, msg, mlen)

    所以在这个里面进行，由于log_info中含有sys_id选项，其实呢，可以向多个子系统发送消息, 也没啥毛病

    一个hdl下面只是有一大堆可用的svr，svr没有绑定到固定的sys_id, hdl也没有绑定到固定的sys_id


-----------------------
Wed May  3 16:01:56 CST 2017

UPEL
1. coreutils的深入调研
1.1 textutils 测试总结
举例说明coreutils能完成的功能：？？？

1.2 sh-utils 测试总结

举例说明sh-utils能完成的功能: ? ? ?

1.3 fileutils 测试总结

2. coreutils分享材料准备

预期分享的形式？

大类 > 单个命令介绍

几个问题：
为啥这些exe被组合到一起
组合起来？


1. 先完成工具的测试
2. 写一个wiki(中心点？以上tool为什么组合到一起，组合起来能做些什么事情？）
为什么不能sudo cd 之类的？
如何能组合起来?
看样子如果2做不起来就直接做掉1吧
anyway 
start with 1



