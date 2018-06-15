# upredis-tests

## tcl

tcl的设计受shell影响较大，但是补全了shell中缺少的namespace
param package scope file socket等缺失特性。

package
source
set
::
proc
{}
[]
''
""
dict
args
global
upvar
argc
argv0
argv
pkg_mkindex
load
_

socket
fconfigure

end

exec


## tcl-redis

c/s模型，多进程socket通信。

### 使用方式

./runtest --help 
--valgrind         Run the test over valgrind.
--accurate         Run slow randomized tests for more iterations.
--quiet            Don't show individual tests.
--single <unit>    Just execute the specified unit (see next option).
--list-tests       List all the available test units.
--clients <num>    Number of test clients (default 16).
--timeout <sec>    Test timeout in seconds (default 10 min).
--force-failure    Force the execution of a test that always fails.
--help             Print this help screen.

--tags <-denytag|allowtag>
--client <port>
--port
--accurate 

### c/s模型

test_server_main
    accept_test_clients
        read_from_test_client

消息格式
<bytes>\n<payload>\n 

c-->s: <status> <details>
status包括：ready, testing, ok, err, exception, done
s-->c: <cmd> <data>


需要注意的是这里的c/s与redis-server，redis-client概念不同。

测试中的c完成了启动svr，连接svr，发起命令和收集结果；
测试中的s完成测试任务分发，测试结果收集，测试客户端管理。


### 小结



