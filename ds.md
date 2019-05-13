分布式系统
---

# 分布式事务

## 协议

### 2PC


```
XA START “outer-1”;

insert …;
select …;
update …;

XA END “outer-1”;
XA PREPARE “outer-1”;

//wait all prepare
XA COMMIT “outer-1”;
```

问题：

- 为什么Commit一定能成功，如果commit不成功会怎样？
- `XA COMMIT`或者`XA ROLLBACK`失败了怎么办？
- 同样地，PREPARE和COMMIT阶段的超时/未决怎么办？

### 3PC


## 解决方案

### DTP

### TCC

https://www.liangzl.com/get-article-detail-525.html
https://github.com/changmingxie/tcc-transaction
https://dbaplus.cn/news-159-1929-1.html

### MQ


### 异步确保

### 本地消息表

### 消息中间件

### TCC模式




