# 内存管理

clogs 内存管理采用zmalloc内存分配器，并将一个脱敏任务涉及的内存分配合并到一块
内存减少内存申请次数。

## zmalloc

zmalloc是对jemalloc/tcmalloc/libc-malloc的简单封装。

内存管理采用redis的内存管理zmalloc, 主要出于以下考虑：

1. 简单
2. libc-malloc和jemalloc之间切换方便(valgrind测试）
3. 在redis项目中验证过性能

## 服务端内存管理

服务端处理 读取->脱敏->落盘 的结构称为 clogs task，该结构合并了报文处理
过程中需要的内存分配。


```

/*
 * clogs task：
 *
 * +----------+-------------+-----------------+-------------+
 * |clogs_task|head_reserved|{clogs head; msg}|tail_reserved|
 * +----------+-------------+-----------------+-------------+
 *                  |       |           |
 *                  /       /           /
 *                save    clogs       msg
 *              落盘地址  clogs报文  消息地址
 *
 * clog_task        : clogs_task结构体（与消息放在一起，减少内存分配次数）
 * head_reserved    : 落盘的头部（时间戳，分隔符等）预留空间
 * clogs head       : clogs报文头部（变长）
 * tail_reserved    : clogs尾部（分隔符等）预留空间
 *
 */

```
   
## 客户端内存管理

hdl持有一个buffer，每次组包使用buffer存储，buffer大小不够时翻倍。


# 脱敏插件系统

由于通信报文格式, 规范多样，因此将格式解析和替换的代码分离到插件中。

## 概要设计

```
[MAPS.01]
soname = libkv.so
exp = hello

[CUPS.01]
soname = libkv.so
exp = world
```

一些概念:

- 子系统: MAPS, CUPS等
- 报文格式: kv, 8583, xml, tlv等
- 报文规范 

    规范01 《中国银联银行卡交换系统技术规范 第2部分 报文接口规范》 （境内卷）
    规范02 《中国银联支付标记化服务接口技术规范》 7.5.2.1　去标记化
    ...

- 脱敏规则:

每种规范对应一种脱敏规则，该规则规定了哪些域（子域，字节）需要被脱敏。
规则由插件进行解析。



在一个子系统中，报文格式可以相同，但是报文规范唯一。


## 详细设计

### API

clogs\_rep\_plug.h: 插件头文件,规定了插件需要实现的函数

```
/* 
 * clogs rep plugins should implement following functions 
 */ 

void *clogs_rep_plug_create(const char *expr);
int clogs_rep_plug_sub(void *plug_ctx, char **msg, int len);
void clogs_rep_plug_destroy(void *plug_ctx);
```

clogs\_rep.h:脱敏模块头文件, 脱敏模块接口

```c
typedef void *(*clogs_rep_plug_create_t)(const char *expr);
typedef int (*clogs_rep_plug_sub_t)(void *exp, char **msg, int len);
typedef void (*clogs_rep_plug_destroy_t)(void *exp);

typedef struct clogs_rep {
    clogs_rep_plug_create_t   clogs_rep_plug_create;
    clogs_rep_plug_sub_t      clogs_rep_plug_sub;
    clogs_rep_plug_destroy_t  clogs_rep_plug_destroy;

    void                *plug_ctx;
    void                *plug_so;
    char                *plug_soname;
} clogs_rep_t;

clogs_rep_t *clogs_rep_create(const char *soname, const char *expr);
int clogs_rep_sub(clogs_rep_t *clrs, char **msg, int len);
void clogs_rep_destroy(clogs_rep_t *clrs);
```

### 脱敏流程

1. 初始化

	读取配置文件，获得报文规范列表，建立对应的脱敏上下文哈希表(key：
	子系统+报文规范，value:脱敏上下文）。

2. 脱敏

	根据报文的子系统+报文规范找到对应的脱敏上下文，执行脱敏

3. 销毁

	销毁脱敏上下文列表


