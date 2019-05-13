
# mysql

## 101

启动

- `mysqld_safe`用来启动作为mysqld的守护程序，并且尝试恢复？

创建用户


连接


使用


问题：

- 什么是wsrep？
- mysqld没有守护功能吗/systemd为什么用了其他方案替代mysqld_safe？

## 管理运维

用户和权限

## 协议

### 基本数据类型

Integer Types

- 包含Protocol::FixedLengthInteger和Protocol::LengthEncodedInteger

String Types

- 包含Protocol::FixedLengthString, Protocol::NulTerminatedString, Protocol::VariableLengthString:, Protocol::LengthEncodedString, Protocol::RestOfPacketString

### MySQL Packets

If a MySQL client or server wants to send data, it:

- Splits the data into packets of size (224−1) bytes
- Prepends to each chunk a packet header

比如说`01 00 00 00 01`表示1B payload, 序号0, QUIT(0x01)命令.

### Generic Response Packets

a) OK_Packet

- header(第一字节)0x00表示OK/EOF packet
- payload包括header/affected_rows/last_inserted_id/status_flags/warnings/

```
07 00 00 02 00 00 00 02    00 00 00
```

b) ERR_Packet

- header 0xff表示ERR
- payload包含header/error_code/sql_state_marker/sql_state/error_message

c) EOF_Packet

deprecated from 5.7.5

d) Status Flags

### Text Protocol

- 为什么是Text Protocol，还有binary？
- 为什么text protocol只有20个命令的定义，alter table等其他命令的呢？
- 为什么每种命令的应答结果集都不一样？由于不一样，所以必须mysql client需要知道上下文/aka，做sql解析？
- 另外cap flag？

a) result set

```
{<column count>}{<column def>+}{[EOF]}{resultsetrow+}{ERR|OK} 
如果在结束的OK包中含有MORERESULT标记，则后续还有resultset。
```

### Prepared Statements



### Character Set

### Connection Lifecycle

#### Connection Phase

处理握手和auth。

#### Command Phase

处理命令

### 碎碎念

- 客户端连上之后，server先发greeeting，header 0x0a表示v10协议？
- mysql不是1请求1应答的交互模型，那么怎么知道mysql客户端怎么知道应答结束了？server怎么知道客户端请求结束了？

卧槽，从协议上看，mysql比redis的协议要复杂的多。

而且客户端也会发起一些隐藏的query。

## 复制

## API

## 业界


## 参考材料


https://dev.mysql.com/doc/refman/5.7/en/innodb-storage-engine.html
http://baijiahao.baidu.com/s?id=1601880124183644788&wfr=spider&for=pc

# Innodb存储引擎

## ACID Model

C是什么意思？是不是脏读就是非consistent？

二手资料对于C的解释：

一致性指的是数据库需要总是保持一致的状态，即使实例崩溃了，也要能保证数据的一致性，
包括内部数据存储的准确性，数据结构（例如btree）不被破坏。

InnoDB通过doublewrite buffer 和crash recovery实现了这一点：
前者保证数据页的准确性，后者保证恢复时能够将所有的变更apply到数据页上。
如果崩溃恢复时存在还未提交的事务，那么根据XA规则提交或者回滚事务。
最终实例总能处于一致的状态。

另外一种一致性指的是数据之间的约束不应该被事务所改变，例如外键约束。
MySQL支持自动检查外键约束，或是做级联操作来保证数据完整性，
但另外也提供了选项foreign_key_checks，如果您关闭了这个选项，
数据间的约束和一致性就会失效。有些情况下，数据的一致性还需要用户的业务逻辑来保证。


关于doublewrite buffer：


关于crash recovery：


## MVCC

undo log分为insert和update两类，其中insert undo在事务提交后可以删除；
update undo需要确认没有其他事务正在使用当前undo log。

实现方式上需要考虑到mysql的行结构包含以下属性：

```
6B DB_TRX_ID
7B DB_ROLL_PTR
6B DB_ROW_ID
```

## Locking and Transaction Model


### Locking

- InnoDB implements standard row-level locking where there are two types of locks, shared (S) locks and exclusive (X) locks.
- *Intention locks* are table-level locks that indicate which type of lock (shared or exclusive) a transaction requires later for a row in a table

- A *record lock* is a lock on an index record.

```
SELECT c1 FROM t WHERE c1 = 10 FOR UPDATE;
```

- A *gap lock* is a lock on a gap between index records, or a lock on the gap before the first or after the last index record. 

```
SELECT c1 FROM t WHERE c1 BETWEEN 10 and 20 FOR UPDATE;
```

gap lock merge???

Gap locks in InnoDB are “purely inhibitive”, which means that their only purpose is to prevent other transactions from inserting to the gap. 

- A *next-key lock* is a combination of a record lock on the index record and a gap lock on the gap before the index record.
??
- An insert intention lock is a type of gap lock set by INSERT operations prior to row insertion.
??
- An *AUTO-INC* lock is a special table-level lock taken by transactions inserting into tables with AUTO_INCREMENT columns.

问题：
为啥需要表锁？为啥行锁获取之前要获取意向锁？IX与表锁的关系？为什么IX和IX能兼容？


碎碎念：

sql界面上，锁的操作接口为`select ... (lock in share mode|for update)`, 所有的更新sql(insert/update/delete)默认都是加锁的。

https://segmentfault.com/a/1190000014133576
http://mysql.taobao.org/monthly/2016/01/01/
https://juejin.im/entry/59104bdea0bb9f0058a2a1db
https://juejin.im/post/5b82e0196fb9a019f47d1823

### Transaction Model


#### 隔离级别

文章中反复提到的集中并发异常：

- sql2003中描述读异常：主事务读取收到次事务的并发冲突影响。
- Jim Grey提到的写异常：dirty write（回滚掉了不是自己的修改）和lost update（覆盖掉了不是自己的修改）
- 语义约束?
- 不一致？

- The default isolation level for InnoDB is REPEATABLE READ.
- InnoDB supports each of the transaction isolation levels described here using different locking strategies. 

问题：

- 为什么要把不可重复读和幻读区分开来?

幻读是针对结果集合而不是行的现象:不可重复读针对行，幻读针对集合。

- RR是如何实现的？

从wikipedia的描述，可以看出vanilla的RR就是通过行锁实现的，因此RR级别下能保证可重复读，但是不保证不出现幻读。

从业界实现上看，innodb出现幻读、pg/sql-server不出现幻读。

- 为什么myrocks的RS不是RR？两者的区别点在哪里？rocksdb为什么不实现RR，能不能实现RR，如何实现RR？


#### autocommit, Commit, and Rollback

- By default, MySQL starts the session for each new connection with autocommit enabled


## 内存架构

### Buffer Pool

- implemented as a linked list of pages
- data that is rarely used is aged out of the cache using a variation of the LRU algorithm.
- `SHOW ENGINE INNODB STATUS`

### Change Buffer

- The change buffer is a special data structure that caches changes to secondary index pages when those pages are not in the buffer pool. 
- 缓存的二级索引的增量部分？

### Adaptive Hash Index

literally adaptive hash index

### Log Buffer

log缓存

## 磁盘架构

### Tables

- An InnoDB table and its indexes can be created in the system tablespace, in a file-per-table tablespace, or in a general tablespace. 
- When innodb_file_per_table is enabled, which is the default, an InnoDB table is implicitly created in an individual file-per-table tablespace
- MySQL stores data dictionary information for tables in .frm files in database directories. Unlike other MySQL storage engines, InnoDB also encodes information about the table in its own internal data dictionary inside the system tablespace.
- The default row format for InnoDB tables is defined by the innodb_default_row_format configuration option, which has a default value of DYNAMIC
- Always define a primary key for an InnoDB table

```
CREATE TABLE t1 (a INT, b CHAR (20), PRIMARY KEY (a)) ENGINE=InnoDB;
SELECT @@default_storage_engine;
SHOW TABLE STATUS FROM test LIKE 't%' \G;
SELECT * FROM INFORMATION_SCHEMA.INNODB_SYS_TABLES WHERE NAME='test/t1' \G;
```

### Indexes

聚簇索引、二级索引

### Tablespaces

The InnoDB system tablespace contains the InnoDB data dictionary (metadata for 
InnoDB-related objects) and is the storage area for the doublewrite buffer, the
change buffer, and undo logs. The system tablespace also contains table and 
index data for user-created tables created in the system tablespace.

```
SELECT TABLE_NAME from INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='mysql' and ENGINE='InnoDB';
```

#### General Tablespaces

多个小表的组合表空间？

```
CREATE TABLESPACE tablespace_name
    ADD DATAFILE 'file_name'
        [FILE_BLOCK_SIZE = value]
                [ENGINE [=] engine_name]
```

####  Undo Tablespaces

Undo tablespaces contain undo logs, which are collections of undo log records that contain information about how to undo the latest change by a transaction to a clustered index record.

```
SELECT @@innodb_undo_tablespaces;
```

#### The Temporary Tablespace

Non-compressed, user-created temporary tables and on-disk internal temporary tables are created in a shared temporary tablespace. 

### InnoDB Data Dictionary

The InnoDB data dictionary is comprised of internal system tables that contain metadata used to keep track of objects such as tables, indexes, and table columns. The metadata is physically located in the InnoDB system tablespace. For historical reasons, data dictionary metadata overlaps to some degree with information stored in InnoDB table metadata files (.frm files).

### Doublewrite Buffer

为什么需要doublewrite？
怎么做到doublewrite？

### Redo Log

WAL?

## Row Formats

The InnoDB storage engine supports four row formats: REDUNDANT, COMPACT, DYNAMIC, and COMPRESSED.

## Configuration
