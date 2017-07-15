# clogs-客户端

本文档补充描述clogs客户端的配置文件动态生效、高可用、负载均衡设计方案。

## 配置动态生效


```
get clt config version v
if v > cur:
    get clt config c
    init hdl with c
```

## 高可用

高可用采用被动触发策略，在应用发送日志的同时做ha探测，图示参见[概要设计](clrs_1.0.0)。

1. ping/pong报文([协议](clogs-proto))
2. 非阻塞读取pong报文
3. 自动隔离/恢复

NOTE:
- 隔离过程中有一部分报文丢失
- 隔离和恢复过程将更新ketama continuum

实现：

```
if (util_timercmp(&svr->next_ha_chk, &now, <=)) {
    /* 超过探测间隔仍未收到有效回复 */
    if (svr->ha_chk_state == PING) { 
        rc = drain_ack_nonblock(svr, &ack);
        
        if (rc || !ack_valid(svr, ack)) {
            svr->ha_invalid_cnt ++;

            if (svr->ha_invalid_cnt >= MAX_HA_CHK_INVALID_CNT) {
                isolate_svr(hdl, svr);
            }
        }
    }

    /* 超过探测间隔，发送ping报文 */
    svr->ping_id += 2;
    ping_svr(svr);      
    util_timeradd(&now, &interval, &svr->next_ha_chk);
    svr->ha_chk_state = PING;

} else {
    if (svr->ha_chk_state == PING) {  
        rc = drain_ack_nonblock(svr, &ack);

        if (!rc && ack_valid(svr, ack)) {
            svr->ha_chk_state = PONG;

            if (svr->isolated) {
                recover_svr(hdl, svr);
            }
        }
    }
}
```

## 负载均衡

为了尽量降低svr增加/减少造成的影响，采用一致性哈希算法, 按照文件名进行哈希。

### 一致性哈希

以对象(object)缓存(cache)作为案例描述。

- 出发点

hash(object)%n  hash(object)%(n-1) hash(object)%(n+1) 

大多数object的哈希值改变, 大量对象将未命中缓存。

- 哈希空间

哈希空间为32bit的值空间，范围0~2^32-1。

![circle](attachment:circle.jpg)

- 将object映射到哈希空间

通过hash将object映射到哈希空间。

```
hash(object1) = key1;
.....
hash(object4) = key4;

```

![object](attachment:object.jpg)

- 将cache映射到哈希空间

```
hash(cache A) = key A;
....
hash(cache C) = key C;
```

![cache](attachment:cache.jpg)

- object对应到cache

cache和object都映射到同一个hash空间，object对应的哈希值顺时针找到的第一个
cache就是object对应的cache。

- 添加/删除cache

如果删除cache B，那么之前映射到B的object将转移到C；

![remove](attachment:remove.jpg)

如果增加cache D，那么之前映射到C的一部分object将分流到D;

![add](attachment:add.jpg)
    
- 虚拟节点

如果部署的节点数量很少，那么很可能会出现分布不均的情况。解决该问题的方法是引入虚拟节点概念。

虚拟节点是真实节点的多个复制，这些复制代表一个真实节点。如果需要删除一个真实节点，
那么所有对应的虚拟节点都将删除。

![virtual](attachment:virtual.jpg)


由于虚拟节点和真实节点是多对一的关系，因此映射到虚拟节点之后，相应的真实节点也确定了。

```
objec1->cache A2; objec2->cache A1; objec3->cache C1; objec4->cache C2
```
![map](map.jpg)

参考: [Consistent-hashing](https://www.codeproject.com/Articles/56138/Consistent-hashing)

### clogs负载均衡

1. 参考twemproxy中的ketama,哈希算法采用MD5
2. 按照文件名称进行哈希
3. 隔离/恢复svr及扩缩容时出现节点增删



### 缺点

- 日志文件位置不能指定
