
* 服务端进程编写:

twemproxy：

1. 一个进程一个实例 instance
    instance 的存在避免了全局变量的存在，能构成更加清晰的条线
    直接使用栈内存创建instance。
    
    instance 包括进程级别资源：ctx, conf_filename, log, loglevel, pid,
    pid_filename等（不能放进ctx中的资源）。

    
2. instance 有一些默认配置 default_options
    比如说：配置文件地址, 默认日志级别，默认日志文件等。


3. 同时有一些自定义的配置

    自定义的配置可以通过命令行参数给出，命令行参数设置instance属性值。

    3.1 命令行
        通常只需要设置instance级别的配置即可;
        有些像Mysql的服务器, 可以在命令行中覆盖配置文件中的配置

    3.2 配置文件

    3.3 使用帮助/verion
        通用的命令行参数：-h, -V, -v, -p, -o
        帮助：通常包含version


4. 运行 instance
    4.1 prerun
        进程级别的初始化：日志初始化，demonize, 创建pidfile, 打印欢迎消息

    4.2 run

        主要是ctx的创建，运行，销毁。之所以需要ctx是因为可能会有扩展为多线程。
        扩展为多线程时，需要考虑将进程级别和ctx级别分离。

        4.2.1 create ctx
            读取配置文件
            ctx 初始化配置

        4.2.2 loop ctx

        4.2.3 destroy ctx
            create ctx反向操作

    4.3 postrun

        清理prerun创建的资源



* 如何daemonize一个进程
  
  messy, so don't do that



----
卧槽，c项目真的是一个项目一种风格！
memcached烧脑
twemproxy处女座
redis?
so，不要太执念
