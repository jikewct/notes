2017年第三季度

1. clogs
客户端TCP方案，编码，测试
功能测试框架调研，编码，测试
对比集中实现与应用实现日志脱敏性能

2. redis
upredis-api-java入maven仓库
钱包jedis超时问题的复现与定位
支持TSM对upredis-api-java的选型，并针对思考TSM提出的issue的解决方案

3. 操作系统
upel代码管理方案整理
upel-1.0.2 版本复测
分享coreutils，procps-ng知识

4. 网络与虚拟化
suse/rhel的硬件兼容性调研
虚拟机: bridge和NAT网络配置理解
xen虚拟机调研，安装xen物理机&虚拟机
验证复现内存申请卡顿问题, 发现没有kvm和xen虚拟机都无法复现生产上内存卡顿现象
tcp链路异常情况测试整理和分享

5. upel-1.0.3项目
upel-1.0.3 poc
unixbench  : 外部组件引入
upel-lsb   : debranding
upel-comps : 定制银联运维与性能测试组件
rpm限制安装: 方案调研，阅读rpm&yum源码，编写restrict-installl插件，测试

6. 协程
调研goroutine，c#，lua，python，boost协程实现原理
阅读libco，lthread, coroutine, libgo协程实现代码
调研结果进行整理总结分享，讨论对于协程组件的需求
对比libevent和libco实现客户端，服务端，代理三种业务场景的开发效率和性能


