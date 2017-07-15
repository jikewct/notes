NAME

       iperf - 网络吞吐量测试工具

SYNOPSIS

       iperf -s [ options ]

       iperf -c server [ options ]

       iperf -u -s [ options ]

       iperf -u -c server [ options ]

DESCRIPTION

       CS结构，能测试TCP、UDP的网络吞吐量。

GENERAL OPTIONS

       -e, --enhanced 显示增强报表信息

       -f, --format [kmKM]  单位

       -i, --interval n 每隔n秒输出统计信息

       -l, --len n[KM] 设置缓存大小为n

       -m, --print_mss 打印TCP mss

       -o, --output filename 输出报告到filename

       -p, --port 设置端口(默认5001）

       -u, --udp 使用udp

       -w, --window n[KM] 设置TCP窗口大小 (socket buffer size)

       -z, --realtime 要求实时调度

       -B, --bind host bind到host

       -M, --mss n 设置mss

       -N, --nodelay 设置TCP no delay, disabling Nagle's Algorithm

       -V, --IPv6Version ipv6

       -x, --reportexclude [CDMSV] exclude C(connection) D(data) M(multicast) S(settings) V(server) reports

       -y, --reportstyle C|c if set to C or c report results as CSV (comma separated values)

SERVER SPECIFIC OPTIONS

       -s, --server 启动server模式

       -U, --single_udp 单线程udp模式

       -D, --daemon daemon模式

CLIENT SPECIFIC OPTIONS

       -b, --bandwidth n[KMG] | npps 设置目标带宽（默认1Mbit/s）

       -c, --client host 客户端模式

       -d, --dualtest 双向测试

       -n, --num n[KM] 传输量（instead of 时间）

       -r, --tradeoff 分别做双向测试

       -t, --time n 持续时间（默认10s）

       -B, --bind ip | ip:port bind

       -F, --fileinput name 从文件输入数据

       -I, --stdin  从stdin输入数据

       -L, --listenport n 双线测试listen端口

       -P, --parallel n 并发数量

       -T, --ttl n 多播ttl

       -Z, --linux-congestion Linux拥塞控制算法 set TCP congestion control algorithm (Linux only)
