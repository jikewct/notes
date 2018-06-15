# moray-upredis


# 集成测试框架

采用twemproxy中使用的python编写的框架。

## 分析

lib/conf.py 定义各binary的绝对路径

lib/base_modules.py: 提供了服务器抽象Base类，DBPMServer，以及Sock类

Base：

对RedisServer，Sentinel，DBPMServer，Memcached，Nutcracker等组件进行抽象：
- 构造要素：name, host, port, path
- 目录要素：bin, etc, log, data
- Sub class should implement: _alive, _pre_deploy, status, and init self.args

- 抽象操作：

deploy:
    _pre_deploy: 通常是拷贝bin，生成配置文件
    _gen_control_script: 生成 ./$name-control.sh <start|stop> (start: $starcmd, stop: $runcmd)

start:
    cd $path && ./$name-control.sh start
    等待直到 self._alive

stop:
    cd $path && ./$name-control.sh stop
    等待直到 !self._alive

clean:
    rm -fr $path

pid:
    pgrep -f $runcmd

_run:
   system(rawcmd, logging.debug)

host:
    return self.args["host"]

port:
    return self.args["port"]

需要重写的方法和属性：

_alive: 判断server启动完成
status: 对于redis-server，sentinel都是up_in_seconds
除了构造函数中需要传入的name，host，port，path，args["startcmd"] args["runcmd"]需要定义


lib/utils.py: 提供了util函数，断言函数。



