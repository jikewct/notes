# zk

配置文件管理中心。

## 概念

client
server
ensemble
leader
follower

path
znode

read
sync
write
consensus 
zxid

## C client

API:

```
zookeeper_init
zookeeper_close
zoo_set_debug_level

zoo_aget                    data            global?
zoo_awget                   data            user
zoo_aset                    stat            no
zoo_acreate                 string          no
zoo_adelete                 void            no
zoo_aexists                 stat            global?
zoo_awexists                stat            user
zoo_aget_children           strings         global?     
zoo_awget_children          strings         user
zoo_aget_children2          strings_stat    global?
zoo_awget_children2         strings_stat    user
zoo_async                   string          no
zoo_aget_acl                acl             no
zoo_aset_acl                void            no

zoo_create
zoo_delete
zoo_exists
zoo_get
zoo_wget
zoo_set
zoo_set2
zoo_get_children
zoo_wget_children
zoo_get_children2
zoo_wget_children2
zoo_get_acl
zoo_set_acl

```

数据结构：

```

sync_completion {
    rc
    u {str|data|acl|strs2|strs_stat}
    complete
}

zhandle_t {

    primer_storage
    primer_buffer
    primer_storage_buffer

    sent_requests :  completion_head_t: [completion_list_t] {
        xid

        c : completion {
            type
            (dc):void|stat|data|strings|strings_stat|acl|string|watcher_result
            clist
        }
        data

        watcher : watcher_registration_t {
            watcher: watcher_fn
            context
            checker: result_checker_fn
            path
        }

        buffer : buffer_list_t {
            buffer
            len
            curr_offset
            next : buffer_list_t
        }

        next
    }

    completions_to_process

    to_send : buffer_head_t : [buffer_list_t]

    input_buffer
    to_process : buffer_head_t : [buffer_list_t]

    active_node_watchers: { path -> watcher_object_list_t : [watch_object_t : {
        watcher :watcher_fn
        context
        next
    }]}
    active_exist_watchers
    active_child_watchers

    outstanding_sync
    complete


}

```

- 每个buffer_list包含一个完整的record，每个record由header+req组成，send buffer时先发送定长4字节长度
- master线程: 粘包;`completion->sent_requests`,`buffer_list->to_send`
- IO线程: WRITE: `to_send->/dev/null`; READ: `bptr<-to_process, deserialize_ReplyHeader, sent_requests->cptr, activateWatcher(cptr->watcher), cptr->buffer=bptr, cptr->completions_to_process`
    - activateWatcher: 根据rc选择watcher ht，挂载watcher到ht
- completion线程：`cptr<-completion_to_process, deserialize_ReplyHeader, deserialize_response: 根据返回值类型的不同，调用不同的回调函数dc`

### watch

watch触发是怎么通知到server, server什么反应？


server怎么通知到client,client怎么反应？

IO线程: 通过WATCHER_EVENT_XID通知client，客户端collectWatchers，把结果挂载到completions_to_process
completion线程中: deliverWatchers

- server发送的WATCHER_EVENT_XID分以下类型：

    - CREATED_EVENT_DEF -- node, exist
    - CHANGED_EVENT_DEF -- node, exist
    - CHILD_EVENT_DEF -- child
    - DELETED_EVENT_DEF --  child, node, exist

collectWatchers: 将/path对应的watcher摘除，放到cptr中

deliverWatchers: 执行每一个watcher cb。


- 同一个客户端相同类型watch同一个目录多次，最后只触发一次


```
get /foo 1
get /foo 1
stat /foo 1

# 只触发一次watcher
set /foo bar
```

- 同一个客户端不同类型watch同一个目录多次，最后每个类型触发一次


```
ls / 1
get /foo 1
stat /foo 1

# 触发两次watcher，分别为node create:/foo, node children changed:/
set /foo bar
```


### request


### response

PING_XID
WATCHER_EVENT_XID
SET_WATCHES_XID
AUTH_XID
ELSE_XID

### mt

设计概要：

- 包括master，io，completion三个线程
- master线程：调用api，发起create/get/set/watch/ls等操作
- io线程：while (notclosing); do {interest, poll, process}; done
- completion线程：while (notclosing); do { wait completion; process_completions }; done

### 问题

- 同步接口为什么需要另辟线程？
- 同步接口和异步接口可以混用？
- jute? 
- watcher和completion分别啥时候调用？



