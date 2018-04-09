# upredis-api-c


- README有点业余啊
- upredis_log_set_handle? wtf!!
- open_conn与 connect connect_with_auth connect_with_timeout??
API范式有点混乱！！
- free_reply_object?为什么不直接free_reply
- set_timeout? connect超时控制了吗？
- 长短链接的原理上的区别？

使用上的迷惑？

set_option的，key，value（类型）

为什么不使用sys/queue，而放入无关的tailq.h

另外为什么设计那么多的vcommand，command

设计文档呢？

为什么拿到的不是直接的hiredis？

不依赖于commons-pool这样的组件的话，pool策略是什么样的呢？

minIdel，maxTotal，block when exhausted, evictor？

testOnBorrow, testOnIdle, testOnReturn

reload操作涉及的问题

好奇葩啊，居然提供了直接链接指定ip，port，timeout，passwd的接口

为什么把svr_info和passwd与其他的option区分开来？不能统一到option中？

reload操作的话，哪些东西能reload，哪些东西不能reload？

Wlog什么的会不会影响性能，要不要perf或者gperf一把。


------------------
options:
struct upredis_option;
upredis_option_init(struct upredis_option *opt);
upredis_option_set(struct upredis_option *opt, int k, const void *v, int vlen);
upredis_option_get(struct upredis_option *opt, int k, void **v);
upredis_option_deinit(struct upredis_option *opt);


conn:
struct upredis_conn;
upredis_conn_open(struct upredis_conn *conn);
upredis_conn_open_persist(struct upredis_conn *conn);
upredis_conn_open_auth(struct upredis_conn *conn)?
upredis_conn_open_persist_auth?
upredis_conn_close(upredis)

handle:
struct upredis;
int upredis_init(struct upredis *uprds, struct upredis_option *opt);
int upredis_init_from_cfg(struct upredis *uprds, char *cfg);
void upredis_deinit(struct upredis *uprds);
void upredis_set_log_callback(struct upredis *uprds, logcb);

----------------------

设计目标：

- 后端接多个upredis-proxy，提供负载均衡、连接池、高可用功能；但是不提供分片功能，分片功能有upredis-proxy提供


- 单个redis，提供连接池功能？
- 多个redis，提供分片功能
- 多个redis，提供分片&连接池功能
- 多个proxy，提供连接池，负载均衡，高可用

关于高可用和分片：有待讨论

--------------------------------
- 目前hiredis好像是针对单个redis的链接功能，其他的类似 JedisPool，ShardedJedis，
    ShardedJedisPool，JedisSentinelPool的功能都么有！

- upredis实际上是做了hiredisPool，添加了负载均衡和高可用，后面只能链接proxy或者单个redis
    （单个redis，直接用hiredis; 多个redis，由于没有分片，所以也没有用）



--------------------

几个不能理解的问题：
1. 为什么提供直连接口
2. 为什么提供长连接
3. 重构是否需要保持API一致

------------------------

如果让我重新设计：

1. 全部短连接使用
2. evictor有必要，因为idle的健康状态堪忧
3. reload 只能用reload option


-----------------------------

计划： 先把1.1.0上的已有的issue解决，发个patch版本，然后再考虑重构问题,再发个大版本，包括API变动和其他.


----------------------------
review代码吧！

- 卧槽，redisConnectWithTimeout？redis能很优雅地控制connect超时！！！
- 使用了cdb-pub的日志模块，内存模块，dbpm模块
- 含有三种连接： 长连接，短连接，自定义连接
- 用了两类锁：svr锁->conn锁->计数锁；
- 获取短连接: 先选择svr;然后选择svr->free_conns.head；如果没有，则创建一个conn；如果创建失败，则换下一个svr；
- 关闭短连接：放到池中或者删除（如果svr已经被删除，或者conn出问题了），并释放资源；
- 获取长连接：先选择svr；然后创建persist_conn，并添加到svr->persist_conns;如果创建失败，则换下一个svr；
- 关闭长连接：直接从svr中删除，释放资源；
- 获取自定义连接：malloc upredis_conn, 直接调用hiredis获取，并设置rctx
- 关闭自定义连接: 直接释放资源
- 关于密码：支持无密码，本地密码，dbpm密码；加密方式支持无加密，SHA256
- reload操作: 支持对svr_info和passwd进行reload
- 关于隔离恢复操作：
    隔离：取连接的时候，如果svr出错了，那就计算一次错误；如果累计的错误数量超过了阈值，那就割了吧；
    恢复：每次open都恢复一次,对于长连接还要rebalance一下；先把状态不ok的svr清理下链接，然后同步地连接一把redis,成功的就恢复。
- 为啥我还没有看到偷换链接的操作:
    每次操作都会尝试替换恢复和替换连接（！！)，这个性能消耗还是不少的！



-----------------
需要重新梳理下长连接和自定义连接存在的意义；


-------------
隔离操作：
每个命令都会检测，并且计数隔离；如果正确使用连接的话，也没什么问题；
恢复操作：
open_conn, open_persist_conn时，只要当前有需要recover的svr，那么遍历并找到svr，对其进行recover（会先删除freeConns)

问题为什么在隔离svr的时候，没拿走的连接直接销毁，如何处理已经被拿走的连接？ 貌似没有处理
那么如果这部分连接还回来怎么办？

如果在reload中删除了某个svr，并且该svr被隔离，那么该svr的游离连接close时会发生什么？


被隔离的svr会被怎么操作？free?: no, 空闲连接被清除，状态被置为SVR_ERR
被reload删除的svr又会怎样？free？free_conns被free，used_conns, persist_conns没有都被free，svr被free。


所以说返还连接的时候，有可能svr已经不存在了, i.e. conn->svr == NULL

隔离回复的标志是svr-status，fail_cnt虽然记录的次数。

经过以上考证，在清零fail_cnt可以更加合理地抵抗网络抖动！

回头思考api-java能不能做类似的事情：发现api-java无法做到，因为直接拿到的就是Jedis连接，而Jedis连接的操作不会通知api-java，因此做不到清零。这又暴露出来一个问题：网络抖动造成的fail_cnt会在api-java中累积，从而造成隔离（其实是不太合理的）retureResource是否应该清零呢？？？


------------------

上次关于proxy后端超时问题引发的思考：
- redis pipeline是处理完了一个pipeline之后一起发送结果吗？还是说一部分一部分读，然后再一部分一部分写？
- 如果redis的一条线路上的一个大pipeline导致处理时间很长，会不会导致其他的线路starve？如果会starve，如何避免这种starve？

- 为什么twemproxy使用单链接？好像也支持多连接？
- 如果支持多连接，那么在某个链接断掉或者超时，那么积压在该链路上的请求是否转移到其他链接？
- 对于性能来讲，其实单链接不会比多连接差，但是如果多连接的话？

- pipeline的接收时尽量接收的！

------------------------
- 我擦，居然没有权值
- reload操作只会删除svr，增加svr；不会删除used_conns，不会重新负载长连接（那么所谓的重新负载的作用在哪里？）
- 长连接在什么时候会进行连接替换；长连接，openconn触发了svr恢复，
- rebal的意思是在recover的时候会

- 如果应用使用方式为command,command, getreply, getreply这样的话，有可能就会因为偷换链接造成结果混乱！但是如果command，getreply这种方式就不会有什么大问题


综上： 偷换链接只有在recover时才会在长连接侧发生，偷换的思路：只要当前的command/open触发了恢复，那么当前链接被重新负载到别的svr！
另外在偷换链接的时还是采用同步生成链接！可能出现非必要的超时

另外评估重新负载的必要性！

为什么只有触发recover的那个长连接才有必要rebal？还是说rebal是附带功能？


-----------------------
关于version
每次upredis_command都会进行版本检查，如果当前长连接的版本号小于upredis版本，那么就会重新负载，偷换链接,偷换链接的动作实在command之前做的，因此只要是command之前的reply都已经获取完成了，也不会出什么问题；
所以说reload会进行rebalance操作！

free_conns & used_conns的版本有效果吗？没有
为什么recover动作不会触发版本号变更？因为没必要被！

-------------------------
_uprds_create_conn_from_svr->_uprds_create_conn


实现思路：
1. recover中使用的同步操作换成非阻塞！

那么其他的同步操作：

rebal中使用的同步操作？
rebal策略：
    随机一个svr:e，如果e与当svr:s同一个，则不用rebal；否则
    e作为起点，循环遍历队列，从e中创建一个链接tmp（同步操作）；
    然后用tmp替换当前ctx

possible issue：
该issue同时存在于长连接的reload和recover操作中：
- 如果reload添加了一个不可达的svr，由于reload操作触发长连接rebalance，而rebalance操作会遍历svr尝试创建新的连接，而该操作同样有可能造成阻塞；

但是由于基本上该操作是由于应用造成的，而且本来创建连接也会出现阻塞，现象也容易观测到，所以也不算是个issue。


经过分析可知：其他操作不会引发与宕机类似的问题，因此只需要conn ping的时候执行非阻塞操作就好！



----------------------------

方案评审的一些问题：
1. lib多线程可能会带来的一些问题，主要是给多进程的程序带来了哪些风险，比如说errno，信号量
:: 从搜索结果来看，轻易是找不到相关的信息的，只能通过经验和实践以及源码分析来解决以上问题。

2. zdogs是如何考虑多线程的问题的？
:: 暂时不打算分析zdogs的源码来解决这个问题


------------------------------------

关于为何要每隔5s就reset一次，能不能不reset，能不能通过次数控制轮转频率？

每隔5秒reset一次是因为需要控制状态机的流转频率（每个svr 5s之内最多状态机轮回一次，状态
机轮回一次是需要比较多的资源的：创建socket，建立连接，发送报文等）

不能不reset：因为不reset的话无法开启下一轮状态轮转；如果要控制轮转的频率，那么就必须通过
时间来控制。

--------------------------------------
使用状态机的问题：
- 不能立马恢复svr，需要好几笔交易触发
- 如果只剩一个svr的话，需要好几次open才能触发

现在我怎么觉得，通过降低connect的超时时间来控制恢复也不失为一种好办法。



---------------------------------

系统测试记录：

有很多案例没有COND，也就是只有测试没有预期，这样的话除了能测是否core，并不能测试其他点。

有些测试案例应该放在FAQ中！

1.  test_init
预建连接10
建立连接数量1000，连接数量为1000

2. test_svr_down_on_init
预建连接不成功，则放弃
多次open之后，down svr被隔离

3. test_short_basic
测试短连接基础

4. test_isolate_cnt
测试隔离触发的次数

5. test_persist_basic
测试长连接基础

6. test_double_close
测试double close一个连接

7. test_svr_down
测试svrdown情况下的ha功能

8. test_svr_isolate_recover
测试svr down然后up之后的隔离恢复功能

9. test_reload
reload的多种情况，具体参考注释

10. test_dbpm_update_passwd
更新dbpm密码






