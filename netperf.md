NAME
       netperf - 网络性能测试工具


SYNOPSIS

       netperf [global options] -- [test specific options]


DESCRIPTION

       Netperf可用于测试多种不同的网络性能指标，目前聚焦在TCP/UDP批量数据传输和请求相应性能。

   GLOBAL OPTIONS

       -4     IPv4 传输控制信息

       -6     IPv6 传输控制信息

       -f GMKgmk 单位

       -H name|ip,family 目标主机

       -i max,min 为了达到置信率可以尝试的迭代次数范围

       -j     指示Netperf统计附加信息： MIN_LATENCY, MAX_LATENCY, P50_LATENCY, P90_LATENCY, P99_LATENCY,  MEAN_LATENCY and STDDEV_LATENCY.

       -I lvl,[,intvl] 设置置信率(either 95 or 99 - 99 is the default)

       -l testlen 测试持续时间

       -L name|ip,fam 指定本地主机

       -N     不建立控制连接

       -p   指定端口

       -P 0|1 开启或者关闭banner

       -s seconds 先sleep seconds在传输数据

       -t testname 测试类型
                     TCP_STREAM
                     TCP_SENDFILE
                     TCP_MAERTS
                     TCP_RR
                     TCP_CRR
                     UDP_STREAM
                     UDP_RR
                     DLCO_STREAM
                     DLCO_RR
                     DLCL_STREAM
                     DLCL_RR
                     STREAM_STREAM
                     STREAM_RR
                     DG_STREAM
                     DG_RR
                     SCTP_STREAM
                     SCTP_STREAM_MANY
                     SCTP_RR
                     SCTP_RR_MANY
                     LOC_CPU
                     REM_CPU

       -T lcpu,remcpu netperf被lcpu或者rcpu限制

       -v verbosity




NAME
       netserver - netperf 服务器


SYNOPSIS

       netserver [-4] [-6] [-d] [-h] [-L name,family] [-p portnum] [-v verbosity] [-V]


DESCRIPTION

       Netserver  listens  for connections from a benchmark, and responds accordingly.  It can either be run from or as a standalone daemon (with the -p flag). If
       run from the -p option should not be used.

