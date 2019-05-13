# upsql-proxy

## mysql相关概念

### user

### session

## adm

分布式upsql-proxy ha管理

## supervise

supervise线程，mysql协议，upsql-proxy管理端口，处理proxy管理命令。

proxy的管理命令包括：

```
SHOW_PROXY_SESSION
SHOW_PROCESSLIST
SET_OPTION
KILL
```
## frame

主循环

主循环的元素包括哪些？

## handle

```
KILL
INIT DB
PROCESS LIST
FIELD LIST
```

透传：

- handle_create_pass_through/backend_pass_through/frontend_send_result
- 后端datanode由配置文件决定

分库：

handler_dispatch_by_sql：

- 复杂查询发送到meta，简单查询按照isud不同操作进行分库。

目前看来分库的逻辑至少包括：table info、hash func、meta等逻辑，暂时先不管。
分库完成之后，会生成一个plan，plan包含了各shard需要执行的sql的树形结构。

碎碎念：

- 使用方式上分为：透传模式和分库模式
- `报文解析->SQL解析->生成plan->执行plan`
- mysql的命令在proxy上基本体现为：COM_QUERY/COM_PROCESSLIST/COM_DUMPGTID...

## execute

前后端线程/plan/executor怎么组织的？
reentrent??

## protocol

报文解析？

## parse

语法解析的结果是啥样的？怎么使用语法解析的结果？

## shard

## annotation

## backend

## frontend

## metadata

## thread

```
 frame {
     threads: //所有线程
 }
```

目前的线程包括:

- main: 负责listenfd-RP-frontend_con_accept，通过p2p从main下发到event
- event: 负责处理main下发的fd-R-frontend_con_handle，处理与前端的握手，AUTH，读取并解析mysql协议的报文，handler_dispatch根据不同的cmdtype选择不同的逻辑处理
- supervise
- meta 
- mover 
- xa-exception

## handle

frontend:

> frontend_con_handle

```
INIT->SEND_HANDSHAKE->READ_HANDSHAKE->SEND_AUTH->READ_AUTH->CHECK_AUTH->SEND_AUTH_RESULT->
(READ_QUERY->READ_WAIT->LOGIC_PROCESS->SEND_QUERY_RESULT)*
```
mysql packet完整之后才recv下来/每个packet保存为一个chunk放到conn->recv_queue中

backend:

### handler_dispatch (透传模式)

KILL: 

- frame中保存了{usr->links}哈希表
- proxy的thread-id > 100
- 可以kill proxy链接或者backend链接（需要向后转发）
- 转发kill到upsql并且转发应答

upsql和proxy的client id的对应关系？

BINLOG:

- 支持binlogdumpgtid和binlogdump

其他:

- plan {backend_pass_through}

### handler_dispatch (分库模式)

COM处理：

```
COM_PING:

COM_FIELDLIST:

COM_PROCESSKILL:

COM_INIT_DB:

COM_PROCESS_INFO:

COM_STMT_xxxx:

COM_SHUTDOWN:

COM_BINLOG_DUMP:

COM_QUERY:

`handler_dispatch_by_sql->handler_dispatch_by_sql_shard`

```

DDL:

- handle_create_metadata_ddl 

DML:

- 简单isud：shard_isud
  - 对于多表/子查询/union等 转发meta
  - shard_insert:
    - 对于多行/无字段信息等 转发meta
    - 其他 handle_create_tx_execute_multi
    - 分库输入包含分库表和分库字段列表，分库输出包括？
    - 对于自增列/`_hash_index`

  - shard_select
  - shard_update_or_delete

- 复杂sql: handle_create_metadata_dml，适用于replace/call/do/load_data/load_xml
- handler: handle_handler_read_by_shard
- 事务和锁：仅支持begin/commit/rollback

drdb_schema:

- distribute_version_inf(instance, version)： 全局共享的版本号？
- distribute_shard_map_inf(group, modulo, datanode, schema, extend_su_datanode, extend_su_datanode): 
- distribute_table_inf(schema, table, shard_columns, auto_increment_column, group, type, value)
    - type包括 shard_lua_script/shard_lua_expression/shard_udf/singleton/broadcast
- distribute_datanode_inf(datanode)

- 关于分片：
    - shard_get_table_inf
    - shard_dual_config: 
    - vitual_database
    - real_table
    - virtual_table

- 部署在哪里? DDL? 怎么创建和初始化？

其他：

- utility：handle_create_metadata_master, 适用于explain/help/describe 
- use: handle_create_change_database
- checksumtable: handle_create_metadata_dml
- table-maintain: handle_create_metadata_master
- set: handle_create_set_option
- show: handle_create_metadata_master
- 不支持账户管理以及其他命令

DRDB: 

- handle_create_add_datanodes
- handle_create_data_load_balance
- handle_create_table_load_balance
- handle_create_remove_datanodes
- handle_create_add_shard_group
- "select datanode, status, crt_ts from drdb_schema.distribute_datanode_inf  order by datanode"
- "select * from drdb_schema.distribute_ddl_inf"
- handle_create_ddl_flush
- handle_create_all_datanode_execute



### handler_dispatch （读写分离）

## reentreent & executor

reentreent的核心思路是跳过已经执行的代码行。

界面:

```
REENTRANT
REENTRANT_ONCE
REENTRANT_REDO
REENTRANT_STEP
REENTRANT_GOTO
REENTRANT_SYNC_EXECUTE
REENTRANT_FINISH_SUCCESS
REENTRANT_FINISH_FAIL
REENTRANT_WAIT_OTHER
```

DS:

```
struct reentrant_t
{
    gint status;/*成功 失败  正在处理*/
    gint in_process;/*在处理  1->0 说明进入处理， 变为1 表示处理结束*/
    reentrant_function parent_reentrant_function;/*父节点*/
    void * parent_plan;
    /*
     * 用以区分是否为同一次call，
     *     1. 当call_diff不同,且前一次已完成或没有前一次调用，
     *           则自动重置reentrant，这样就可以再次调用了执行了
     *
     **/
    void *param;

    reentrant_function reentrant_function;
    plan_action_t      *reentrant_plan;
    u_hash_t* local_data;

    gint line;
    gint times;

    gboolean from_goto;

    u_allocator_t *ref_mem_allocator;

    u_hash_t  *sub_reentrants;
};

struct reentrant_set
{
    u_hash_t        *rerntrant_map;
    u_allocator_t   *ref_mem_allocator;
};

struct plan_action_t
{
//    guint   idx;
    u_string_t *path;

    packet_string_t *ref_packet; /* request packet */

	guint    cmdtype;
	packet_string_t *ref_sql;

	gchar    *datanode;
	gchar    *database;
    gchar    *schema;   /* 分schema下指定schema */
	gboolean is_master;
    guint32  sql_id;    /*用于prepare中的sql id*/
	gboolean sql_is_write; /* 写操作 */
	shard_result_row_t   *ref_shard_result_row;

	u_ptr_array_t        *sub_action_array;
    plan_action_t        *ref_parent_plan_action;

	front_connection_t   *ref_front_connection;
	backend_connection_t *ref_backend_connection;
	session_t            *ref_session;

	reentrant_func_t     func_reentrant;
	reentrant_func_t     func_exception_handle;
	UNREENTRANT_FUNC     func_unreentrant;
	PACKAGE_FUNC         func_package;
	RSPFRONT_FUNC        func_rspfront;

	reentrant_set_t     *reentrant_set;
	u_allocator_t       *ref_mem_allocator;
	guint                affect_rows;

    long long handler_id;
};

```
executor_plan_process



- 每个reentrant的top都是executor_asyn_process
- 没有任何的setjmp/longjmp的操作？怎么做到跳转到parent？libevent怎么结合？


## mover

??



