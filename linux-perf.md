# perf

linux内核提供的性能监测调优工具。

## 第一印象

[如何读懂火焰图？](http://www.ruanyifeng.com/blog/2017/09/flame-graph.html)

阮一峰的这篇文章给出linux-profiling简单直观的第一印象。

## perf(perf_events) 简介

perf也称perf_events, 是linux内核提供的性能调试机制。

perf是基于事件的观察工具，可用于找到系统的性能瓶颈，使用perf能回答以下问题：

- 为什么CPU消耗大，系统当前热点是什么？
- 那个调用引发了CPU L2 cache miss？
- 某个系统函数是否被调用，频率是多少？
- 那些调用触发了TCP消息发送？


perf命令包括：

```
annotate        Read perf.data (created by perf record) and display annotated code
archive         Create archive with object files with build-ids found in perf.data file
bench           General framework for benchmark suites
buildid-cache   Manage build-id cache.
buildid-list    List the buildids in a perf.data file
data            Data file related processing
diff            Read perf.data files and display the differential profile
evlist          List the event names in a perf.data file
inject          Filter to augment the events stream with additional information
kmem            Tool to trace/measure kernel memory properties
kvm             Tool to trace/measure kvm guest os
list            List all symbolic event types
lock            Analyze lock events
mem             Profile memory accesses
record          Run a command and record its profile into perf.data
report          Read perf.data (created by perf record) and display the profile
sched           Tool to trace/measure scheduler properties (latencies)
script          Read perf.data (created by perf record) and display trace output
stat            Run a command and gather performance counter statistics
test            Runs sanity tests.
timechart       Tool to visualize total system behavior during a workload
top             System profiling tool.
trace           strace inspired tool
probe           Define new dynamic tracepoints

```

NOTE:
- perf需要使用root权限运行
- 在虚拟机和物理机上perf支持的event类型不同
- 由于perf发展活跃，因此upel, suse上的功能差别比较大

## one-liner

列出Events：

```
# Listing all currently known events:
perf list

# Listing sched tracepoints:
perf list 'sched:*'

```

Events计数：

```
# CPU counter statistics for the specified command:
perf stat command

# CPU counter statistics for the specified PID, until Ctrl-C:
perf stat -p PID

# CPU counter statistics for the entire system, for 5 seconds:
perf stat -a sleep 5

# Various basic CPU statistics, system wide, for 10 seconds:
perf stat -e cycles,instructions,cache-references,cache-misses,bus-cycles -a sleep 10

# Count block device I/O events for the entire system, for 10 seconds:
perf stat -e 'block:*' -a sleep 10
```

性能调优：

```
# Sample on-CPU functions for the specified command, at 99 Hertz:
perf record -F 99 command

# Sample on-CPU functions for the specified PID, at 99 Hertz, until Ctrl-C:
perf record -F 99 -p PID

# Sample on-CPU functions for the specified PID, at 99 Hertz, for 10 seconds:
perf record -F 99 -p PID sleep 10

# Sample CPUs at 49 Hertz, and show top addresses and symbols, live (no perf.data file):
perf top -F 49

```

静态跟踪:

```
# Trace new processes, until Ctrl-C:
perf record -e sched:sched_process_exec -a

# Trace all context-switches, until Ctrl-C:
perf record -e context-switches -a

# Trace context-switches via sched tracepoint, until Ctrl-C:
perf record -e sched:sched_switch -a

# Trace all context-switches with stack traces, until Ctrl-C:
perf record -e context-switches -ag

# Trace all context-switches with stack traces, for 10 seconds:
perf record -e context-switches -ag -- sleep 10
```

动态跟踪:

```
# Add a tracepoint for the kernel tcp_sendmsg() function entry ("--add" is optional):
perf probe --add tcp_sendmsg

# Remove the tcp_sendmsg() tracepoint (or use "--del"):
perf probe -d tcp_sendmsg

# Add a tracepoint for the kernel tcp_sendmsg() function return:
perf probe 'tcp_sendmsg%return'

# Show available variables for the kernel tcp_sendmsg() function (needs debuginfo):
perf probe -V tcp_sendmsg
```

混合:

```
# Sample stacks at 99 Hertz, and, context switches:
perf record -F99 -e cpu-clock -e cs -a -g 
```

报告:

```
# Show perf.data in an ncurses browser (TUI) if possible:
perf report

# Show perf.data as a text report, with data coalesced and percentages:
perf report --stdio

# Report, with stacks in folded format: one line per stack (needs 4.4):
perf report --stdio -n -g folded

# List all events from perf.data:
perf script --header

# List Current evnets
perf evlist -v
```

## Prerequisite

安装：

```
# suse
zypper install perf

# upel
yum install perf

```

符号：

perf和其他的调试工具类似，也需要符号信息（用于将地址转换为符号名），如果没有
符号信息，运行perf将会得到类似于如下的stack：


```
   57.14%     sshd  libc-2.15.so        [.] connect           
               |
               --- connect
                  |          
                  |--25.00%-- 0x7ff3c1cddf29
                  |          
                  |--25.00%-- 0x7ff3bfe82761
                  |          0x7ff3bfe82b7c
                  |          
                  |--25.00%-- 0x7ff3bfe82dfc
                   --25.00%-- [...]

```

如果出现以上情况，可以通过CFLAGS添加`-fno-omit-frame-pointer`解决。如果没有
frame pointer，那么perf无法正常获取stack信息。由于gcc默认`omit-frame-pointer`
（能获得大约1%）的性能提升，因此建议应用程序添加此编译选项。

perf在kernel 3.9之后支持使用`-g dwarf`作为workaround，但经过试验sles11sp2, upel
目前均不支持（所以还是需要重新编译）。

另外有VM的语言（Java，Node，Python等），perf需要语言进行支持。具体参考[perf example](http://www.brendangregg.com/perf.html#JITSymbols)


## Events

Events可以分为三类：Hardware Events, Tracepoints, Software Events.

`perf list`能列出所有events（注意需要使用root权限执行）:

关于perf events的解释参考`man perf_event_open`


```
List of pre-defined events (to be used in -e):

  branch-instructions OR branches                    [Hardware event]
  branch-misses                                      [Hardware event]
  bus-cycles                                         [Hardware event]
  cache-misses                                       [Hardware event]
  cache-references                                   [Hardware event]
  cpu-cycles OR cycles                               [Hardware event]
  instructions                                       [Hardware event]
  ref-cycles                                         [Hardware event]

  alignment-faults                                   [Software event]
  context-switches OR cs                             [Software event]
  cpu-clock                                          [Software event]
  cpu-migrations OR migrations                       [Software event]
  dummy                                              [Software event]
  emulation-faults                                   [Software event]
  major-faults                                       [Software event]
  minor-faults                                       [Software event]
  page-faults OR faults                              [Software event]
  task-clock                                         [Software event]

  L1-dcache-load-misses                              [Hardware cache event]
  L1-dcache-loads                                    [Hardware cache event]
  L1-dcache-stores                                   [Hardware cache event]
  L1-icache-load-misses                              [Hardware cache event]
  ...

  branch-instructions OR cpu/branch-instructions/    [Kernel PMU event]
  branch-misses OR cpu/branch-misses/                [Kernel PMU event]
  bus-cycles OR cpu/bus-cycles/                      [Kernel PMU event]
  cache-misses OR cpu/cache-misses/                  [Kernel PMU event]
  cache-references OR cpu/cache-references/          [Kernel PMU event]
  cpu-cycles OR cpu/cpu-cycles/                      [Kernel PMU event]
  ...

  block:block_bio_backmerge                          [Tracepoint event]
  block:block_bio_bounce                             [Tracepoint event]
  block:block_bio_complete                           [Tracepoint event]
  block:block_bio_frontmerge                         [Tracepoint event]
  block:block_bio_queue                              [Tracepoint event]
  ...
  xfs:xfs_trans_read_buf_shut                        [Tracepoint event]
  xfs:xfs_unwritten_convert                          [Tracepoint event]
  xfs:xfs_update_time                                [Tracepoint event]

```

### Hardware Events(PMCs)

Performance Monitoring Counters(PMC)是CPU提供的计数器硬件，可以统计诸如指令执行数量
和cache-miss之类的数据。这些硬件基础设施提供了动态跟踪执行的应用，进行热点侦测的基础。

### Software Events

单纯的linux kernel software events; e.g. cpu-clock, context-switches, minor-faults.

`perf record` suse默认的cpu-clock（一个高精度的的时钟），upel默认为cycles（硬件时钟）
因此默认perf record按照固定的频率采样。

### Tracepoints

tracepoints是内核代码中的埋点，比如在system call, TCP/IP 事件，文件系统操作等。这些
埋点在不使用perf时几乎对性能没有影响。perf命令可以开启这些埋点，用来收集stack和
timestamp信息。此外，perf也可以使用kprobe和uprobe框架动态创建tracepoint。

关于tracepoint的统计信息如下：

```
# perf list | awk -F: '/Tracepoint event/ { lib[$1]++ } END {
      for (l in lib) { printf "  %-16.16s %d\n", l, lib[l] } }' | sort | column

    block          19	    kvmmmu         14	    rpm            4
    compaction     3	    libata         6	    sched          23
    context_tracki 2	    mce            1	    scsi           5
    drm            3	    mei            2	    signal         2
    exceptions     2	    migrate        2	    skb            3
    fence          8	    module         5	    sock           2
    filelock       6	    mpx            5	    sunrpc         26
    filemap        2	    napi           1	    syscalls       592
    ftrace         1	    net            9	    task           2
    gpio           2	    nfsd           18	    timer          13
    hda            5	    oom            1	    udp            1
    hda_controller 6	    pagemap        2	    vmscan         15
    hda_intel      4	    power          20	    vsyscall       1
    i915           39	    printk         1	    workqueue      4
    iommu          7	    random         6	    writeback      25
    irq            5	    ras            3	    xen            35
    irq_vectors    22	    raw_syscalls   2	    xfs            367
    kmem           12	    rcu            1	    xhci-hcd       9
    kvm            52	    regmap         15
```

关于perf events的详细解释：

- `man perf_event_open`
- [perf-events-documentation](https://stackoverflow.com/questions/13267601/perf-events-documentation)

另外hardware events与CPU的设计相关，相关的event需要参考vendor specific文档:

Intel PMU event tables: Appendix A of manual [here](http://www.intel.com/Assets/PDF/manual/253669.pdf)
AMD PMU event table: section 3.14 of manual [here](http://support.amd.com/us/Processor_TechDocs/31116.pdf)


## perf stat (统计)

perf stat能够给出所有events的统计信息，默认情况下输出cache-misses，cache-references等信息。

```
perf stat gzip file1
perf stat -B dd if=/dev/zero of=/dev/null count=1000000             # 统计默认events
perf stat -e cycles dd if=/dev/zero of=/dev/null count=1000000      # 统计CPU cycles，both user & kernel 
perf stat -e cycles:u dd if=/dev/zero of=/dev/null count=100000     # 统计CPU cycles，only user
perf stat -e cycles:uk dd if=/dev/zero of=/dev/null count=100000    # 统计CPU cycles，both user & kernel explicitly

perf stat -e r1a8 -a sleep 1                                        # 统计vendor specific r1a8（16进制）events
perf stat -e cycles,instructions,cache-misses [...]                 # 统计多种信息
```

每种event都可以添加modifier（e.g. context-switch:u)来指定观察user, kernel,
guest, host等不同范围。

modifiers:

| Modifiers | Description                                               | Example |
| --------- | -----------                                               | ------- |
| u         | monitor at priv level 3, 2, 1 (user)                      | event:u |
| k         | monitor at priv level 0 (kernel)                          | event:k |
| h         | monitor hypervisor events on a virtualization environment | event:h |
| H         | monitor host machine on a virtualization environment      | event:H |
| G         | monitor guest machine on a virtualization environment     | event:G |


更多关于PMC的使用信息参考[perf-tutorial](https://perf.wiki.kernel.org/index.php/Tutorial#Introduction)


## perf record/report (性能调优)

默认perf record采样输出的文件为./perf.data，如果当前已经有perf.data，那么该文件将被覆盖。

如果需要将perf record的采样结果放到别的机器上进行分析，可以使用`perf archive`将当前结果打包。

使用perf 默认参数对redis-server,upredis-proxy的进行采样，通过redis-benchmark看不出采样
对于tps有影响，相关材料也显示perf对于性能的影响很小，因此应用在使用perf进行性能调优时
不用担心采样耗费太多性能。


```
perf record -F 99 -a -g -- sleep 30             # 对当前系统(-a)的以99HZ(-F 99)频率采样30s(-- sleep 30)，采样信息包括stack(-g)
perf record -g -p `pidof redis-server`          # 对redis server进程进行采样
perf record -g redis-migrate-tool -c rmt.conf   # 对redis-migrate-tool进程进行采样


perf report --stdio                 # 查看报告
perf report --stdio
```

报告示例如下:

```
# perf report --stdio
# ========
# captured on: Mon Jan 26 07:26:40 2014
# hostname : dev2
# os release : 3.8.6-ubuntu-12-opt
# perf version : 3.8.6
# arch : x86_64
# nrcpus online : 8
# nrcpus avail : 8
# cpudesc : Intel(R) Xeon(R) CPU X5675 @ 3.07GHz
# cpuid : GenuineIntel,6,44,2
# total memory : 8182008 kB
# cmdline : /usr/bin/perf record -F 99 -a -g -- sleep 30 
# event : name = cpu-clock, type = 1, config = 0x0, config1 = 0x0, config2 = ...
# HEADER_CPU_TOPOLOGY info available, use -I to display
# HEADER_NUMA_TOPOLOGY info available, use -I to display
# pmu mappings: software = 1, breakpoint = 5
# ========
#
# Samples: 22K of event 'cpu-clock'
# Event count (approx.): 22751
#
# Overhead  Command      Shared Object                           Symbol
# ........  .......  .................  ...............................
#
    94.12%       dd  [kernel.kallsyms]  [k] _raw_spin_unlock_irqrestore
                 |
                 --- _raw_spin_unlock_irqrestore
                    |          
                    |--96.67%-- extract_buf
                    |          extract_entropy_user
                    |          urandom_read
                    |          vfs_read
                    |          sys_read
                    |          system_call_fastpath
                    |          read
                    |          
                    |--1.69%-- account
                    |          |          
                    |          |--99.72%-- extract_entropy_user
                    |          |          urandom_read
                    |          |          vfs_read
                    |          |          sys_read
                    |          |          system_call_fastpath
                    |          |          read
                    |           --0.28%-- [...]
                    |          
                    |--1.60%-- mix_pool_bytes.constprop.17
[...]
```

关于`perf report`报告的阅读说明：
- 默认stack格式为callee，可以通过`perf report -g caller`或者`perf report -G`切换为caller
- 默认overhead的格式为relative，可以通过参数`-g graph --percentage absolute`修改为绝对值模式
- 默认perf report按照children排序，`perf report --no-children`可以按照self进行排序

### perf report报告阅读

通过`perf script`可以看出`perf record`记录了采样目标的当前执行的symbol（如果使用了-g参数，则
附加记录了stack）。`perf report`通过统计每个symbol出现的概率计算symbol对应的执行耗时。也就是
出现概率越大的symbol，就是hot codepath。

如果使用了`-g`参数，`perf report`包含Chilren和Self两种overhead。假如采样的样本数量为N，其中
Children的统计方式为： 统计symbol出现的次数X（无论该symbol是否在栈顶），Children = X / N;
Self的统计方式为： 统计symbol出现在栈顶的次数Y, Self = Y / N;


### frame graph

perf report只能看到某个symbol的统计信息，不能非常有效地观察整体信息，因此github上有一个开源的
[FlameGraph项目](https://github.com/brendangregg/FlameGraph)能够将perf信息转换成更加直观的svg
图表。

如下图所示是使用apachebench短连接场景下压测httpd服务器的性能：

[httpd.svg]

由于svg图片具有交互特性，能够放大缩小，搜索关键字，鼠标悬浮能显示详细的数据，能够很好地展示
perf数据。


从上图可以看出：

- httpd服务器性能大量耗费在系统调用accept，close也占11%
- accept系统调用的性能几乎全部消耗在lock_sock_nested和release_sock, 说明大量的进程/线程在对竞争同一个listen fd



参考材料:

[perf wiki](https://perf.wiki.kernel.org/)
[perf examples](http://www.brendangregg.com/perf.html)
[FlameGraph](https://github.com/brendangregg/FlameGraph)
[如何读懂火焰图？](http://www.ruanyifeng.com/blog/2017/09/flame-graph.html)

