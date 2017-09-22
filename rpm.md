
# rpm源码分析

- rpm mode分为两大类：
        QV:  qeury(q), verify(K), Querytags(Q), Import(I);
        EIUF: 分为两小类，Erase(MODE_ERASE), Install, Upgrade, Freshen(MODE_INSTALL)


        其中QV包含qva_flags：
        EIUF包含: transactionFlags，probsFilterFlags， installInterfaceFlags.

        其中probsFilter包括:
                 --ignoreos
                 --ignorearch
                 --replacepkgs
                 --badreloc
                 --replacefiles
                 --replacefiles
                 --oldpackage
                 --ignoresize
                 --ignoresize

- 关于rpm relocate的简要说明：http://rpm5.org/docs/api/relocatable.html
  只有一个prefix，--prefix指定；含有多个prefix --relocate OLDPATH=NEWPATH指定


- rpmCliQueryFlags 包含了signature，digest等验证相关的标志，由命令行
  --nodigest, --nosignature等指定


- rpm安装过程分析

## 重要数据结构：


```
struct rpmEIU {
    int numFailed;
    int numPkgs;
    char ** pkgURL;
    char ** fnp;
    char * pkgState;
    int prevx;
    int pkgx;
    int numRPMS;
    int numSRPMS;
    char ** sourceURL;
    int argc;
    char ** argv;
    rpmRelocation * relocations;
    rpmRC rpmrc;
};
```

## 概要分析

========准备阶段

1. 设置vsFlags, 与命令行--nodigest, --nosignature和rpm macros %{_vsflags_erase}, %{_vsflags_install}相关.
2. 设置transFlags，与命令hang--justdb, --test, --no-pre等相关
3. 设置进度callback
4. 处理glob，得到完整文件列表
5. 下载文件，设置eiu
6. 检查rpm文件（tryReadHeader, 得到Header h），处理manifest文件
7. 按照source和binary分类处理rpm安装

[source]
8. 添加sourceURL到列表中

[binary]
8. 检查relocation，设置oldpath
9. 检查freshen条件（installed & version is newer than installed）&& continue
10. rpmtsAddInstallElement

11. 如果没有失败的rpm，则进入下一阶段；否则，退出

==========安装阶段

[binary]
rpmcliTransaction

[source]
rpmInstallSource

==========收尾阶段

释放使用的堆内存
清空ts：rpmtsEmpty
恢复vsFlags



## 详细分析

[binary]

准备阶段: rpmtsAddInstallElement

1. 检查payload格式
2. 如果upgrade，则openDB
3. 创建te
4. 检查是否之前已经添加
5. 如果没有添加，则添加到members中
6. 如果元素需要升级：则添加删除元素


安装阶段：rpmcliTransaction

1. rpmtsCheck: 检查安装依赖
2. rpmtsOrder: rpm拓扑排序
3. rpmtsClean: 清除只有步骤1,2才需要的内存
4. rpmtsRun:   运行transaction

rpmtsRun>

1. rpmtsAcquireLock: 获取事务锁
2. rpmtsSetup: 时间
3. rpmtsSetupTransactionPlugins:
    将%{__plugin_dir}/*.so 添加到rpmtsPlugins中:
        每一个plugin必须定义对应rpm macro: %{__transaction_name}
        该macro第一个参数为插件路径，其余参数为插件选项
        将 plugin 添加到ts之后，会调用相应的 _INIT函数

4. rpmtsSetupCollections: 先不予理会collection相关的内容
5. rpmpluginsCallTsmPre:
    foreach plugin：
        call plugin->TsmPre
    if any Fail, 退出事务

6. runTransScripts(ts, PKG_PRETRANS):
     foreach te in ts:
        rpmteProcess(te, PKG_PRETRANS):
            rpmteOpen: 读取并设置rpmte的Header
            rpmpsmRun(goal): 运行TsmPre脚本
            rpmteClose：reset rpmte的Header为NULL
            rpmteMarkFailed: 如果出现错误，标记为错误

    NOTE: 该阶段出现的异常将被忽略

7. rpmtsPrepare:
    fpcacheCreate
    foreach te in ts:
        skipInstallFiles/skipEraseFiles

    rpmdbOpenAll
    fpcachePopulate
    checkInstalledFiles

    foreach te in ts:
        handleOverlappedFiles
        handle DSI

    foreach te in ts:
        rpmteSetFI(p , NULL)

8. rpmtsProcess:
    foreach te in ts:
        rpmteProcess(te):
            rpmteOpen: 读取并设置rpmte的Header（这就是PsmPre可以获取Header的原因）
            rpmpsmRun(goal): 安装文件
                初始化psm:psmNew, psm->goal, psm->goalname
                rpmpluginsCallPsmPre: 如果返回结果为FAIL，直接跳到PsmPost
                
                安装文件：
                    rpmswEnter : enter stopwatch
                    rpmpsmNext(psm, PSM_INIT):
                        初始化npkgs_installed, scrpitArg, amount, total, fi->apath
                    rpmpsmNext(psm, PSM_PRE)
                        运行trigger，pre脚本
                    rpmpsmNext(psm, PSM_PROCESS)
                        payload = rpmtePayload(psm->te)
                        rpmPackageFilesInstall

                    rpmpsmNext(psm, PSM_POST)
                    rpmpsmNext(psm, PSM_FINI)
		    rpmswExit : exit stopwatch
                rpmpluginsCallPsmPost
                清理psm
            rpmteClose：reset rpmte的Header为NULL
            rpmteMarkFailed: 如果出现错误，标记为错误
        
        rpmdbSync: 同步数据库
            dbiForeach(db->_dbi, dbiSync, 0);
            数据库接口如何设计的？

        无论返回值为啥，都要执行rpmdbSync; 因此这个阶段基本无法终止安装！
        如果在这个阶段终止安装也是不合理的，会出现大量的broken dependency！


9. runTransScripts(ts, PKG_POSTTRANS):
    foreach te in ts:
        rpmteProcess(te, PKG_POSTTRANS)

10. rpmpluginsCallTsmPost:
    foreach plugin：
        call plugin->TsmPre
    NOTE: 该阶段出现的错误，被忽略




===========
TODO
4. TsmPre-->PsmPre是那个操作加载了Header?               rpmteOpen
2. review %{_vsflags_erase}, %{_vsflags_install}的作用，看看能否从这个地方出手, 貌似还是不行的呀
3. tryReadHeader的时候出手？            这样的话就是直接出手，而不是插件！另外实现sig_conf需要一些代码
5. 看看还有没有别的获取Header的方法     差不多也就这样吧


x 1. 添加%__transaction_restrict_install %__sig_conf
7. review日志等级，内存清理，review代码
8. 打包代码，poc
6. 方案编写，测试案例编写，


测试案例需要测试到以下方面：
1. macro: __transaction_restrict_install有没有带来的影响 , __sig_conf
2. --noplugins, --nosignature参数是否符合预期
3. 看看有没有回归测试案例，跑一下回归测试
4. __sig_conf文件的错误格式千万不要导致core！


===========
总结：
1. 按照现在这种做法，在TsmPre中进行检查并限制是合理的做法
2. 由于在install过程中，也出现了多次OpenHeader，ResetHeader操作，因此在TsmPre中获取信息的做法是正确的
3. 目前来讲现在的做法都是对的，因此现在剩下的问题也就是测试，review，打包
