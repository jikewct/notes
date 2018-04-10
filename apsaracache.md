# apsaracache

基于redis-4.0

合集 https://yq.aliyun.com/articles/431206
子嘉、特性描述 https://www.zhihu.com/question/66639526
夏周、容灾 https://yq.aliyun.com/articles/403312
仲肥、redis-4.0解密

## 文件组织

rdb.index
dump.rdb
aof-inc.index
appendonly-inc-unixtime.aof

apsaracache的性能与原生redis性能类似。

## 协议

"psync <runid> <psync_offset> <opid> <server_id> <repl_version> <current_master_runid>" --> "aofcontinue replid"   #添加了aofpsync模式
"opinfo <header>" --> OK/ERR #用于opapply客户端、复制和aofloading；
"aofflush" --> OK/ERR #切换aof文件
"opget <startopid> [count <count>] [matchdb <db>]* [matchkey <key>]* [matchid <serverid>]*" --> "start_opid matched_count <val1> <val2> ..."
"opRestore <key>" --> OK/nil/ERR    #恢复opget得到的数据
"opdel <source> <opid>" --> OK/ERR   # 删除某个opid
"getopidbyaof <aof_filename>" --> :opid/OK/ERR #获取aof文件的起始opid
"forcefullresync" --> OK/ERR #请求强制全同步
"syncreploffset <offset>" --> OK/ERR  #master强制同步slave的reploffset
"syncstate <slave-ip> <slave-port> <FULL|INCR>" --> SYNCED/SYNCING/ERR #查询slave的同步状态


## 配置

protocol redis
aof-max-size 100M
cron-bgsave-rewrite-percentage
auto-cron-bgsave
auto-purge-aof
aof-psync-state
aof-buf-queue-max-size

repl-stream-db
repl-id
repl-offset
repl-id2
repl-second-replid-opid

opdel-source-timeout
opget-max-count
opget-master-min-slaves

server-id 12345678

## 数据结构

server.opdel_source_opid_dict
client.opapply_src_serverid
client.opapply_src_opid

typedef struct redisOpdelSource {
    long long opid;             /* opid sent by opdel command
                                 * that redis can delete to */
    time_t last_update_time;    /* last update time */
} redisOpdelSource;

## FLAGS

client.flags

REDIS_OPGET_CLIENT
REDIS_OPAPPLY_CLIENT
REDIS_OPAPPLY_IGNORE_CMDS

## 问题

- 切换aof的条件

rdbSaveBackground
    |prepareForRdbSave
serverCron
    |aofSplitCron # 超过100M
    |replicationUnsetMaster
    |replicationSetMaster
    |aofFlushCommand
        aofSplit(try_delete, force_split)
            stopAppendOnly
            startAppendOnly
            deleteAofIfNeeded

综上：超过100M、主动flush、复制关系发生变化、rdbSave


- opinfo机制与作用

结构：
redisOplogHeader:
    unsigned version:8; /* version of oplog */
    unsigned cmd_num:4; /* number of commands in one oplog, currently 2 or 3 */
    unsigned cmd_flag:4;
    unsigned dbid:16;
    int32_t timestamp;
    int64_t server_id;
    int64_t opid;
    int64_t src_opid; /* opid of source redis */

通常在一个oplog中，含有opinfo和另一条命令（共2条）；特殊的情况是setex、psetex
该命令将被拆分成两个命令，因此有3个命令。

- 主从复制与aof-binlog

复制过程中aof-psync的做法：
master发送：

slave接收：


## aof_buf_queue


## aof-binlog

feedAppendOnlyFile
    feedAofFirstCmdWithOpinfo #确保aof文件的第一个命令为opinfo
    checkAndFeedAofWithOplogHeader(c, cmd, dictid, del_type); # 如果是opinfoCommand，则不会再添加OplogHeader
        feedAppendOnlyFile(c, server.opinfoCommand, dictid, argv, 2,
    updateSrcServerIdOpid(c->opapply_src_serverid, c->opapply_src_opid); #更新server.src_serverid_applied_opid_dict

综上：给aof中的每个命令，添加opinfo命令；opinfo中包含了时间、opid、sid等丰富的信息；最后更新ssid-opid字典。

## 实现

### master发送

masterTryPartialResynchronization
    masterTryAofPsync: # psync > aofpsync > fullsync
        if (!server.aof_psync_state) return ERR
        if (!server.aof_state != AOF_ON) return ERR

        c->flags |= REDIS_AOF_PSYNCING;
        bioCreateBackgroundJob 后台线程，发送aof binlog到slave
            bioProcessBackgroundJobs:
                bioFindOffsetByOpid
                    atomicGet(server.bio_find_offset_res, offset_result); # bio_find_offset_res是只有一个槽位的buffer
                    //找到aof中opid对应的offset
                    生产到server.bio_find_offset_res # serverCron消费这个result

handleBioFindOffsetResCron
    atomicGet(server.bio_find_offset_res, offset_result);
    listAddNodeTail(server.bio_find_offset_results, offset_result);
    atomicSet(server.bio_find_offset_res, offset_result);
    handleBioFindOffsetRes
        for res in server.bio_find_offset_results:
            switch (res.client)
            case  CLIENT_SLAVE:
                if server.do_aof_psync_send
                    server.aof_psync_slave_offset = tmp_res;
                    masterSendAofToSlave:
                        server.do_aof_psync_send = 0;
                        slave->repldboff = server.aof_psync_slave_offset->offset;
                        EV(slave.fd, WRITE) --> doSendAofToSlave # 读取aof文件，发送到slave客户端

            case REDIS_OPGET_CLIENT:
                tmp_client->opget_client_state->wait_bio_res = 0;
                tmp_res->fp = fopen(tmp_res->aof_filename, "r");
                fseek(tmp_res->fp, tmp_res->offset, SEEK_SET);
                sendOplogToClient(tmp_client); /* send n oplogs to client */

doSendAofToSlave
    while have next aof
        while !eof
            lseek, read, write
        aofReadingSetNextAof

    putSlaveOnline(slave);
    addReplySds(slave,sdsdup(server.aof_buf));
    if (!(server.master && server.master->flags & REDIS_AOF_PSYNCING)) {
        sendSyncReplOffsetCommandToSlave(slave);
        slave->flags &= ~REDIS_AOF_PSYNCING;
    }
    (EV, slave->fd, WRITE) --> del
    resetAofPsyncState

### slave接收

收到的是opinfo+xx命令，通过正常的命令流程执行(read->process->call->propagate)，

slave收到的命令不会回复：

|addDeferredMultiBulkLength
|addReplyString
|addReplySds
|addReply
    prepareClientToWrite #fake client(used to load aof), master, handler setup failed --> return C_ERR
    对于slave，只有master接收到了REPLCONF ACK之后才会真正将客户端缓存发送到slave。

重要的是分析：
- slave对于复制流中的opinfo怎么处理?

opinfoCommand:
    server.next_opid = header->opid + 1;
    /* update src server -> applied opid */
    if (server.server_id != header->server_id) {
        updateSrcServerIdOpid(header->server_id, header->src_opid):
            server.src_serverid_applied_opid_dict[header->server_id] = header->src_opid
    }
    server.dirty++;
    selectDb(c, header->dbid);

- slave的aof怎么生成？是否和master一致?

slave的server_id必须和master一致，否则无法进行sync/psync；因此理论上讲得到的aof文件应该是一样的！

- opapply client

用于主主复制的客户端，也就是BLS-reciver。

- 级联的slave获得的复制流是怎样的？


--------------------

REDIS_AOF_PSYNCING ??
REDIS_OPAPPLY_CLIENT 表示BLS-receiver，


slave如果执行的是aofpsync？如果执行的是psync?
server.server_id slave必须和master一个server_id，否则无法主从复制。


------------------------------------------

c->opget_client_state = NULL;
c->repl_ack_next_opid = -1;
c->opapply_src_opid = -1;
c->opapply_src_serverid = -1;
c->reploff_before_syncreploff = -1;
server.master_repl_offset
server.aof_state

AOF_OFF     #appendonly 配置选项，或者临时被关停了AOF
CLIENT_LUA
CLIENT_FORCE_REPL
CLIENT_FORCE_AOF

---------------------
# 持久化

- 在构建aof_buf时，redis-server将prepend opinfo命令，因此aof_buf字节流将含有opinfo命令。

--------------------
# 复制


---------------------
# opapply

opinfoCommand:
    在opinfoCommand中，redis将根据当前opinfo过滤命令（比如server_id与当前server_id相同，或者opid小于应用过的opid的请求
        c->flags |= REDIS_OPAPPLY_IGNORE_CMDS;

processCommand
    checkOpapplyCmdIgnored
        c->cmd->proc != opinfoCommand && c->flags & REDIS_OPAPPLY_IGNORE_CMDS
        addReply(shared.ignored)

- 在opapply时，循环复制问题通过server_id解决。

- opapply时，propagate aof时，同时会更新 ssid--sopid字典
