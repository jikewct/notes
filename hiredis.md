# hiredis

hiredis对redis的协议进行梳理，指出redis的结果分为：


* **`REDIS_REPLY_STATUS`**:
    * The command replied with a status reply. The status string can be accessed using `reply->str`.
      The length of this string can be accessed using `reply->len`.

* **`REDIS_REPLY_ERROR`**:
    *  The command replied with an error. The error string can be accessed identical to `REDIS_REPLY_STATUS`.

* **`REDIS_REPLY_INTEGER`**:
    * The command replied with an integer. The integer value can be accessed using the
      `reply->integer` field of type `long long`.

* **`REDIS_REPLY_NIL`**:
    * The command replied with a **nil** object. There is no data to access.

* **`REDIS_REPLY_STRING`**:
    * A bulk (string) reply. The value of the reply can be accessed using `reply->str`.
      The length of this string can be accessed using `reply->len`.

* **`REDIS_REPLY_ARRAY`**:
    * A multi bulk reply. The number of elements in the multi bulk reply is stored in
      `reply->elements`. Every element in the multi bulk reply is a `redisReply` object as well
      and can be accessed via `reply->element[..index..]`.
      Redis may reply with nested arrays but this is fully supported.

错误类型:

When a function call is not successful, depending on the function either `NULL` or `REDIS_ERR` is
returned. The `err` field inside the context will be non-zero and set to one of the
following constants:

* **`REDIS_ERR_IO`**:
    There was an I/O error while creating the connection, trying to write
    to the socket or read from the socket. If you included `errno.h` in your
    application, you can use the global `errno` variable to find out what is
    wrong.

* **`REDIS_ERR_EOF`**:
    The server closed the connection which resulted in an empty read.

* **`REDIS_ERR_PROTOCOL`**:
    There was an error while parsing the protocol.

* **`REDIS_ERR_OTHER`**:
    Any other error. Currently, it is only used when a specified hostname to connect
    to cannot be resolved.

In every case, the `errstr` field in the context will be set to hold a string representation
of the error.

---------------------------
感兴趣的问题：

1. hiredis是怎样进行内存管理的，可能对clogs有启发
非常简单的的malloc，realloc；但是该方法不一定会有特别严重的性能问题！

2. hiredis是如何设计异步API的，如何使用该API，对upredis-api-c项目有没有启发
异步的API需要与event库结合。

3. 学习antirez的设计思路，为啥人家的代码那么牛逼

4. hiredis对于printf类似用法的实现！
printf的specifier分为：
[flags][fieldwith][precision][type]

flags:
"#-+ "
# -- 
- -- 
+ -- 
  -- 

fieldwithd:

precision:

type:
int -- diouxX
double -- eEfFgGaA
char -- hh?
short -- h?
long long -- ll?
long -- l?




启示：


- var_arg(ap, type); 必须先知道当前arg的type，才能获取
