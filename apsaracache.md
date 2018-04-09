# apsaracache

基于redis-4.0

https://www.zhihu.com/question/66639526

## 文件组织

rdb.index
dump.rdb
aof-inc.index
appendonly-inc-unixtime.aof

这样看，apsaracache的性能与原生redis性能类似。
同样适用了psync2方案。

## AOF binlog

<opinfo> 

## 协议

"psync <runid> <offset> <opid>"
"aofcontinue replid"
"opinfo <hex>"  #只能用于fakeclient
"opdel <src> <opid>"
"aofflush"

## 配置

aof-max-size 100M

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

## 解决的问题

- 全量同步问题
- PITR问题
- svrid, opinfo?

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

## aof_buf_queue


## aof-binlog

feedAppendOnlyFile
    feedAofFirstCmdWithOpinfo #
    checkAndFeedAofWithOplogHeader(c, cmd, dictid, del_type); # 如果是opinfoCommand，则不会再添加OplogHeader
        feedAppendOnlyFile(c, server.opinfoCommand, dictid, argv, 2,
    updateSrcServerIdOpid(c->opapply_src_serverid, c->opapply_src_opid); #更新server.src_serverid_applied_opid_dict

综上：给aof中的每个命令，添加opinfo命令；opinfo中包含了时间、opid、sid等丰富的信息；最后更新ssid-opid字典。

## 实现

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


消费过程：

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



