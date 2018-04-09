#upredis-proxy

# 主体设计

## 事件库：
- 处理顺序为ERR>READ>WRITE所以会出现：
1）redis断链之后，执行的是core_err->core_close->server_close；
2）如果有一个大的pipeline，proxy可能会一致读取，导致无法及时将请求发送到redis（大pipeline超时）
3) server突然断链那么导致正在等待回复的客户端收到server

- READ常驻/WRITE事件需要的时候添加

- libevent的rw事件可以分别设置为两个不同的event
  nc的事件机制中fd与cb(core_core)一一映射，core_core根据conn,events 按照E->R->W处理事件
  每个conn通过不同的recv,send,close函数指针定制不同的ERW行为。

- loop

a) 处理reload
b) event_wait   # 默认stats_interval 10ms; ctx->max_timeout也为10ms；
c) handle_accumulated_signal
d) core_timeout
e) core_before_sleep

## 消息

```
msg_recv
    while (conn->recv_ready)  # recv_ready==0的情况： EAGAIN; EOF; ERROR
        msg = conn->recv_next # 新msg或mbuf残余的nmsg
        msg_recv_chain  # 读满一个mbuf；对mbuf命令逐个msg解析；解析之后路由到对应的svr

msg_send
    while (conn->send_ready)
        msg = conn->send_next   # siq的迭代器
        msg_send_chain # 一次sendv；sendv之后对mbuf&msg逐个finalize

```

消息流转：

Client  READ: 读取msg; msg --> coq, msg --(forward)--> siq；添加sconn写事件
Server WRITE: siq --> msg; 发送msg；msg --> soq；
Server  READ: 读取pmsg; 与soq.first建立关联；msg从siq出队；添加cconn写事件
Client WRITE: coq --> msg；发送pmsg；soq -->；释放msg--pmsg

解析:

通过状态机实现: tokennize，state，流式, DFA

1)repair：如果token跨两个mbuf，那么将这个token切断到另一个mbuf；
2)again: token未被切断，但mbuf已经被扫描完成
3)ok: mbuf在被扫描完成之前，已经解析到一个完整的msg；如果一个msg跨越两个mbuf，那么该
    msg将悲切分为两个mbuf（i.e. msg与mbuf是一对多的关系）


路由和分片：
conn->recv_done # msg 读取解析完成的后续动作
1) 过滤： quit-在client所有reply收到后关闭连接，auth之前命令不forward，ping命令不forward，管理命令直接回复客户端不支持
2) forward：如果不需要forward，直接回复客户端；如果需要forward，则路由到指定的svr

## 异常处理

几个标记的说明

CLIENT EOF:
由于无法区分客户端到底是close还是shutdown_rd，因此客户端断链当做shutdown_rd处理：
- 由于第二次向close的客户端send会引发EPIPE，因此proxy应该处理EPIPE错误
- 客户端close时，可能msg还没有完全写完，这部分消息将被丢弃
- 半关闭状态的客户端连接还能继续接受svr发来的rsp，因此proxy应该继续向client发送rsp

处理流程：
conn_recv给链路打上eof标记;conn->recv_next丢弃不完整msg；conn停止read；

SERVER EOF:
服务端EOF说明server已经不正常(crash或者错误了)，因此立即关闭链路。

处理流程：
conn_recv给链路打上eof标记;conn->recv_next丢弃不完整msg，标记链路done；conn停止read；
接着由于链路done，关闭server链接:
- 标记siq, soq中的msg为err
- 更新server->next_retry
- 标记server为dead 
- close

SERVER ERR:
过程同SERVER EOF

CLIENT ERR:
立即关闭客户端链接：
- 抛弃非完整req 
- 已经forward的req标记为swallow

协议错误：proxy,redis都直接关闭链接
命令不支持：redis回复-ERR unknown command 'xxx'; proxy将直接关闭链接
- 将conn标记为err
- 客户端/服务端链接被关闭

## 超时处理

core_timeout 根据当前的rbtree计算event_wait等待的时间

如果req超时：
    - 标记conn为ETIMEOUT
    - 断开req所属的链接

为了处理connect超时，sever connect时会向tmo中添加一个fake msg:
- 如果connect正常：连接之后删除该fake msg
- 如果connect超时: fake msg超时，触发断链
以上操作避免了不可达的情况，connect超时需要很长时间


## signals

日志等级up          sigttin
日志等级down        sigttou
重新打开日志文件    sighup
退出                sigint,sigterm(15)
开启reqlog          sigusr1
reload config       sigusr2
coredump            sigsegv


## 断链重连

server的初始化过程：

server_pool_init:
    conf_pool_each_transform:
        server_init:
            conf_server_each_transform: 根据conf初始化server struct
    server_pool_run: 初始化一致性哈希结构

server的链接建立过程：

core_ctx_create:
    server_pool_preconnect:
        server_pool_preconnect_fn:
            server_each_preconnect:
                server_connect:socket, setnonblock, setnodelay, event_add_out, connect

dead之后重连server
core_before_sleep: 
    server_reconnect_check:
        server_connect:socket, setnonblock, setnodelay, event_add_out, connect

autoeject之后重连
req_recv_done:过滤，路由接受到的req msg
    req_forward:
        server_pool_conn: 选择server,选择conn，链接conn
            server_connect:socket, setnonblock, setnodelay, event_add_out, connect

- server的建链过程发生在初始化preconnect，定时检查，req_forward时
- req_forward在server->dead时不connect，并且errno为ETIMEOUT
- reconnect只有在server->dead时进行重连
- dead表示fake eject：如果auto eject，直接eject;否则dead
- 恢复过程为：
server_pool_conn:
    server_pool_update: 根据server_retry_timeout设置的next_rebuild，更新continuum

对于非auto_eject而言，每次断链都会造成server_dead；


综上：
- preconnect，初始化链接(dead=0)
- 断链之后，每个server_retry_timeout之后重连（被动|auto_eject_hosts, 主动|!auto_eject_host)


对于slave创建链接的启发：
- 设置slave的dead=0, 初始化链接，而且preconnect **WITH TIMEOUT**
- 断链之后，每隔server_retry_timeout之后重连

在preconnect成功之前，proxy收到了req怎么办？:
req_recv_done:
    req_forward:
        server_pool_conn: 返回一个connecting或者connected的链接
            server_pool_server
            server_conn
            server_connect
        enqueue siq:

综上： connecting的链接等同于链接好的链接

对于slave链接的启发：
- 发现新的slave之后preconnect
- slave dead 断链之后，每隔server_retry_timeout重连



隔离操作：

trick：server_close实际上的意思是conn_close;

server_each_preconnect:connect失败，关闭连接
    server_close: 如果conn->sd==-1,直接销毁conn;否则，销毁消息队列，然后再销毁conn
        server_failure: 
            server->dead = 1; 或者 server->failure_count++

server_reconnect_check:connect失败，close连接
    server_close

server_pool_conn: connect失败，close连接
    server_close

connection_is_drained:??
    server_close

core_ctx_destroy:
    server_pool_disconnect
        server_pool_disconnect_fn:
            server_each_disconnect:
                conn->close:
...



恢复操作：
a) auto_eject_hosts:
到了next_rebuild之后，对当前需要rebuild的servers，update continuum；
这样的话server被重新添加到可用svrs中

b) !auto_eject_hosts:
到了server->next_retry之后，发起reconnect操作，reconnect成功之后dead=0

关于dead的考究:
server_close:
    server_failure: 
        server->dead = 1; 或者 server->failure_count++
所以对于connection大于1的server，只要一个连接出现错误，则判断server dead是不合理的！

## 密码管理

大体思路： 加密密码>明文密码>dbpm

proxy密码配置：
redis_auth: foobared
redis_auth_s: 1b58ee375b42e41f0e48ef2ff27d10a5b1f6924a9acdcdba7cae868e7adce6bf
dbpms:
    - IP1:PORT1:db1:usr1
    - IP2:PORT2:db2:usr2

实现思路：

conn->need_auth  配置了redis_auth后，链路被标记为need_auth
conn->authing    发送了auth命令之后，链路被标记为authing
conn->dup_auth   pipe_q非空，然后又来了一个auth报文，则链路被标记为dup_auth；
                然后redis_reply时回复DUP_AUTH之后，又将dup_auth标记撤除
AUTH处理流程:
req_recv_done:
    if (msg->noforward):
        req_make_reply:创建reply结构
        msg->reply:(redis_reply)
            如果dup_auth则回复DUP_AUTH
            如果need_auth则回复NEED_AUTH
            如果是auth命令则将auth命令传递到对应的conn:redis_handle_auth_req

        if msg is ping:
            reply pong

redis_handle_auth_req:
    dbpm_select:
        dbpm_connect:
        发送dbpm请求

按照密文>明文>dbpm的级别对比密码


dbpm密码支持：
- conn->usr_auth表示sha256编码的密码，用于与返回的dbpm密码对比
- noforward的命令包括：auth之前的所有命令；ping; auth; auth_s;
- noforward的命令都会直接由conn->reply(redis_reply)处理
- authing过程中的命令全部放在conn->pipe_q中


---- 
nutcracker的策略：
前端的auth命令发送给proxy进行验证；
后端的链接通过add_auth认证；并且对于auth的结果并不判断是否正常。

## 监控管理

之前已经分析过，收到客户端stats命令之后，mgm转发、聚合stats信息，然后再返回客户端
json报文。


分析stats线程与worker线程之间的数据交换，分析为何出现coredump:
stats监控的数据：

```
pool stats:
client_eof          "# eof on client connections"
client_err          "# errors on client connections"
client_connections  "# active client connections"
server_ejects       "# times backend server was ejected"
forward_error       "# times we encountered a forwarding error"
fragments           "# fragments created from a multi-vector request"

server stats:
server_eof          "# eof on server connections"
server_err          "# errors on server connections"
server_timedout     "# timeouts on server connections"
server_connections  "# active server connections"
server_ejected_at   "timestamp when server was ejected in usec since epoch"
requests            "# requests"
request_bytes       "total request bytes"
responses           "# responses"
response_bytes      "total response bytes"
in_queue            "# requests in incoming queue"
in_queue_bytes      "current request bytes in incoming queue"
out_queue           "# requests in outgoing queue"
out_queue_bytes     "current request bytes in outgoing queue"

```

看样子upredis-proxy只是修改了proxy的stats信息获取方式，没有修改stats监控的数据种类：

stats_server_set_ts
    _stats_server_set_ts
        stats_server_to_metric:
        stm->value.timestamp = val


### 总体设计

stats有shadow, current, sum三个stats_pool[]: sum = shadow + current，其中shadow, sum从属于stats aggregator线程
current从属于worker线程，当current move到 shadow时需要使用shadow_lock锁.

struct stats：
- shadow，current，sum
- 各种string
- 链路相关ns_conn_q, s_conn_q， next_retry等
- stats信息数组[] client_eof, server_eof, fragments等

struct stats_pool:
    name
    metric: stats_metic[]
    server: stats_server[]

struct stats_server:
    name
    metric: stats_metric[]

struct stats_metric:
    type
    name
    value

typedef enum stats_type:
    STATS_INVALID,
    STATS_COUNTER,    /* monotonic accumulator */
    STATS_GAUGE,      /* non-monotonic accumulator */
    STATS_TIMESTAMP,  /* monotonic timestamp (in nsec) */
    STATS_SENTINEL


stats aggregate:

stats_rsp_recv_done:
    stats_aggregate:
        locK shadow_lock
        foreach pool:
            stats_aggregate_metric
            foreach server:
                stats_aggregate_metric
        unlock shadow_lock

stats swap:在server处于稳定状态时，每个evloop都进行统计数据交换;server在reloading时不
交换stats信息

stats_swap:
    array_swap(current, shadow)
    stats_pool_reset(current)


stats的初始化和清理：

{core_worker_create, core_mgm_start, core_worker_recreate}
    stats_create:
        stats_pools_create
            stats_pool_map: 分别初始化current, shadown, sum
                stats_pool_each_init
                    stats_pool_init: # 初始化 pool metric
                        stats_pool_metric_init
                            stats_metric_init
                        stats_server_map # 初始化svrs metric
                            stats_server_init
                                stats_server_metric_init: #初始化或者继承统计值
                                    if (GAUGE && !recount)
                                        继承server初始化之前的数值！
                                    else 
                                        stats_metric_init


stats聚合与回复:

创建buf：
stats_create
    stats_pools_create
        stats_create_buf：根据当前的server，slave信息预先buf大小


## 动态生效

ctx->reload_sig 发起reload的标记（kill -SIGUSR2; reload_redis; +switch-master)

ctx->reload_delay: worker try reload again? 标记为reload2，排在当前reload之后的reload请求

ctx->failover_reloading: 

ctx->state:
    CTX_STATE_STEADY,
    CTX_STATE_RELOADING,
    CTX_STATE_RELOADED,

ctx->stats_reload_redis
    STATS_RELOAD_INIT = 0,
    STATS_RELOAD_START, 
    STATS_RELOAD_WAITING, 
    STATS_RELOAD_OK, 
    STATS_RELOAD_FAIL, 

ctx->req_stats
    STATS_REQ_INIT,
    STATS_RELOAD_REDIS,
    STATS_MIGRATE_START,
    STATS_MIGRATE_DOING,
    STATS_RELOAD_REDIS_MIGRATING,
    STATS_MIGRATE_END,
    STATS_STATS,
    STATS_STATS_ALL,


core_loop
    core_before_sleep
        core_reload_check
            if (ctx->stats_reload_redis == STATS_RELOAD_START
                if ctx->state != CTX_STATE_RELOADING:
                    config_reload_redis
                        server_pool_init replacement_pools
                        server_pools_kick_replacement
                        ctx->state = CTX_STATE_RELOADING;
                    ctx->stats_reload_redis = STATS_RELOAD_WAITING;
                else # reloading时，又来了reload命令，即reload2
                    ctx->reload_delay = 1

core_loop
    core_timeout
        core_timeout_reply: 对于超时mgm消息，回应-err timeout
            if (st->alive_cnt == st->cmd_suc_cnt + st->cmd_fail_cnt + st->cmd_timeo_cnt
                && ctx->reload_delay) # 超时，reload2上位为reload
                ctx->reload_delay = 0
                ctx->reload_sig = 1

core_loop:
    if (ctx->state is CTX_STATE_STEADY or CTX_STATE_RELOADED)
        stats_swap
    if (ctx->state is CTX_STATE_RELOADING)
        if server_pools_finish_replacement
            ctx->state = CTX_STATE_RELOADED
        else
            timeout = 10ms

stats_loop
    if worker:
        stats_before_event_wait
            stats_check_reload_redis_finish: 如果WAITING、INIT、START，则返回；如果OK, FAIL则回复相应结果
            
    if master && ctx->reload_sig
        stats_failover_reload:
           if (ctx->req_stats != STATS_REQ_INIT)
               ctx->reload_delay = 1
           else 
               ctx->failover_reloading = 1
               stats_req_forward

stats_rsp_recv_done
    stats_rsp_forward
        stats_make_rsp

stats_req_recv_done
    stats_req_forward
    stats_req_check
        if (msg->type == MSG_REQ_REDIS_RELOAD_REDIS)
            ctx->reload_delay = 1; #如果mgm正在执行其他管理命令，来了reload请求之后，reload排队(reload2)

stats_server_close:
    if (ctx->reload_delay)
        ctx->stats_reload_redis = STATS_RELOAD_START;

### mgm进程：

>>> mgm线程
mgm线程在几乎不对reload有任何影响，只用于响应shutdown命令

>>> stats线程
如果发现当前ctx->reload_sig，则将reload信号分发到各worker；
（分发了reload信号之后，收集reload响应的工作在rsp_recv_done中处理）

>>> monitor线程
侦听+switch-master消息，修改配置文件，将ctx->reload_sig置为1

### worker进程：

>>> stats线程
收到了reload req，则启动reload(ctx->stats_reload_redis = STATS_RELOAD_START)
worker与mgm之间的链路断掉时发现有reload2，则启动reload

定期检查reload是否完成(ctx->stats_reload_redis为OK, FAIL), 并且将结果回复给mgm进程(WAITING)

>>> worker线程
检查reload是否启动(ctx->stats_reload_redis处于STATS_RELOAD_START)如果启动,则执行reload(config_reload_redis)
每个loop都检查reload过程是否完成；如果完成则ctx->stats_reload_redis = STATS_RELOAD_OK


### reload与stats
- reload过程中不会执行stats_swap，也就是说stats信息被冻结了！
- reload完成之后，stat_pools将被重建

隔离时，被隔离的server丢失几笔交易？丢失当前在server上排队的所有交易，所以说：若干笔！

---------------------------
## 异常处理

recv:
core_core
    core_recv
        conn->recv(msg_recv)
            msg_recv_chain
                conn_recv
                    while (eintr)
                        rc = recv
                    conn->recv_ready = 0 if (eagain,err)
                    conn->err = errno if (err)
                    return (err, eagain, n)
    if (core_recv err || conn->done || conn->err)
        core_close
            conn->close
                server_close or client close
### conn异常

#### conn->done

conn->done标志着该conn需要被关闭。

- 对于client来说，conn->done表示client conn已经关闭了write half，并且client conn所有消息都已经
  已经收到了回复

- 对于server来说，只要server eof, rsp stray, 则conn->done，因为除非server异常，否则server是不会主动断链的！

#### conn->err & conn->error

理某个链路的过程中出现了错误，导致链路需要关闭，就可以将errno赋值到conn->err，同时将conn->error置为1

#### conn->eof

链路收到了eof，但需要注意的是client与server对eof的不同处理方式

### msg异常

#### msg->err & msg->error:

标记着该msg在发送的过程中出现了err，需要将向客户端回复msg->err，对应的errstr

core_timeout
    if (msg->error || msg->done)
       skip

server_close
    foreach msg in siq
        swallow or noreply or ...
        msg->done = 1
        msg->error = 1
        msg->err = conn->err
    foreach msg in soq
        swallow or ...
        msg->done = 1
        msg->error = 1
        msg->err = conn->err
        event_add_out(msg->owner)
    discard conn->rmsg
    server_failure
    server_unref
    close(sd)
    conn_put

req_recv_done
    req_forward
        req_forward_error (error forwarding)
            msg->error = 1
            msg->err = errno

req_filter
    req_response_to_client
            req_forward_error
                msg->error = 1
                msg->err = errno
req_forward
    req_response_to_client
            req_forward_error
                msg->error = 1
                msg->err = errno

{rsp_send_next,stats_rsp_send_next}
    req_error
        return msg->error msg->ferror
        如果ferror，则将分片的所有msg都标记为ferror=1

rsp_send_next
    if (req_error(req))
        rsp_make_error
            return msg_get_error(err or ferr) # 将errno转换为errstr


#### msg->done:

表示消息已经确定了回复，比如:收到的rsp，server_close回复errno、被swallow的rsp、
forward过程回复的errno（比如ETIMEOUT）、closing or migrating or need to close
时回复的-ERR closing, migrating, reloading消息、


server_close
    msg->done = 1 

rsp_recv_done
    rsp_forward
        pmsg->done = 1

rsp_recv_done
    rsp_filter
       if pmsg->swallow
           pmsg->done = 1 

req_forward_error: forward过程出现错误，都会直接回复errno到client
    msg->done = 1 

req_response_to_client: forward之前，拒绝forward并直接回复客户端
    msg->done = 1

client_close:
    if msg->done
        log & req_put(msg)

#### msg->swallow

表示收到rsp后不需要向client返回的消息，比如客户端已经放弃的消息，proxy发起的消息(info repl, auth, select, faketimeout)


client_close: 客户端close时，将所有没有完成的req标记为swallow 

server_send_info_repl: 发送info replication的消息被标记为swallow

req_forward:
    if (conn->need_auth)
        msg->add_auth(redis_add_auth_packet): auth命令被标记为swallow

req_send_next:
    if (conn->connecting)
        server_connected:
            conn->post_connect(redis_post_connect): select命令被标记为swallow

server_connect: 用于计算链接超时的消息标记为swallow

#### msg->noforward

表示不需要forward的消息，ping, quit, auth, auth_s, 所有auth之前客户端发送的命令

req_recv_done
    if (msg->noforward)
        if conn->authing, add msg to pipeq
        else 
            req_make_reply 
            msg->reply(redis_reply):对ping，auth，auth_s, ping, auth之前发送的命令，进行相应的回复
            event_add_out

#### msg->noreply

只对memcached有效，表示即使命令出错，server也不给客户端回复任何消息。


## fragment

需要fragment的命令包括del，mset，mget。

rsp_recv_done
    rsp_forward
        msg->pre_coalesce(redis_pre_coalesce)
            pr->frage_owner->nfrag_done++
            对于del，将rsp integer累加到frag_owner.integer
            对于mget，将mbuf移动到实际内容
            对于mset，直接将消息跳过(OK)

req_done: req_done是个神奇函数
    msg->post_coalesce(redis_post_coalesce)
        redis_post_coalesce_mget or ... : 拷贝frag的mbuf，然后回复
        redis_post_coalesce_mset or ... : 直接回复+OK
        redis_post_coalesce_del: 回复累加后的integer

req_recv_done
    msg->fragment(redis_fragment)
        redis_fragment_argx #根据分片规则，将submsgs分配好
    如果没有frag，则发送msg
    如果frag，则发送frag_msgq
            
## quit    

解析到quit命令，将msg->quit置为1；然后req_filter中将该消息丢弃；后续按照客户端断链处理

req_filter
   if (msg->quit)
       conn->eof = 1




## 读写分离

总体设计思路：

1. server添加stats_server[]，用于统计slave指标

2. 考虑slaves队列换成slave列表，这样的话slaves[]可以和stats_slave[]对应

3. info replication slaves变更
- 重建slaves[]，并且重新分配索引（因为stats_slave[]与其对应）
- 重建stat_pools,考虑stats_pool slaves数据继承问题

4. 动态生效
开启：确认能够初始化相应结构，并且添加相应stats结构；将负载分配到slave中
关闭：确认能够正常地清理slave，并且读取请求不在分配到slave；判断reload结束需要考虑到slave

5. 断链重连
- 与master处理类似，断链时直接close，丢失排队的所有msg；断链之后从alive_slaves中移除
- 重连则从重新添加到alive_slaves



测试问题
-------
1. redis_db: 1 会出现core
2. reload完成的判断是否同时需要判断slave状态
3. read_both, read_slaves策略修改
4. 选取slave之后，发现无法创建可用conn，那么应该尝试下一个slave。
5. 两个slave，kill client发现其中一个svr的client connection变成-1，不执行client kill 也变成了0
6. 在超时的情况下，发往slave的请求会hang住整个客户端；但是读写分离之前也是一样的会出现hang!!
7. 在新增或者减少slave时，会出现slave数据被清零


------

master deinit:

a. 初始化不成功，清理退出

b.
{core_worker_conf_regain, core_ctx_create不成功}
    server_pool_deinit
        server_pool_deinit_fn
            server_deinit

c.
server_pools_kick_state_machine
    server_pool_deinit_fn
        server_deinit
d.
server_pools_undo_partial_reload
    server_pool_deinit_fn
        server_deinit


综上： server_deinit出现在server_pool_create撤销，或者reload完成；
sever_deinit，需将server->slaves删除，同时reload完成的判断slave全部完成。


slave deinit:

slave_parse_info: 发现master下面的slave减少了之后，执行disconnect, deinit
    slave_disconnect
    slave_deinit


slave_deactivate: 删slave，slave dead期间

slave_activate: 增加slave，slave非dead期间

-----------------

reload 操作过程：

创建replacementpools，禁止stats swap；建立对应关系（该删掉pool直接删掉，新的pool把pconn转移过来直接可用；old draining
等待完成；

判断完成的过程fold（折叠）判断的过程。


config_reload_redis:
    server_pools_kick_replacement


--------------------
request标记

