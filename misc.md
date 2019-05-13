# 内存泄露测试

使用valgrind命令启动后，valgrind可以在案例运行完成之后给出内存泄露测试报告。

## 命令行

默认:

```
--tool=memcheck
--track-children=yes
--trace-fds=no
--logfile=[STDOUT]
--num-callers=12
--suppressions=[NONE]
--dsymutil=yes
--leak-check=summary
--leak-resolution=high
--track-origins=no
--show-leak-kinds=definite,possible
```

cmake项目:

valgrind --tool=memcheck --track-origins=yes \
--show-reachable=yes --leak-check=full --leak-resolution=high \
--num-callers=20 --dsymutil=yes \
--log-file= valgrind.log --supressions=valgrind.supp <cmdline>


redis-server:

valgrind --leak-check=full --show-leak-kinds=definite --log-file=valgrind.log redis-server redis.conf

## 注意事项

- 优化使用O0
- malloc必须使用libc

## supp

格式:

```

```


常见supp：

```
```


# 覆盖率测试

gcc在编译时，如果CFLAGS和LDFLAGS带有'-fprofile-arcs -ftest-coverage'，编译
出来的binary运行之后产生'.gcno'和'.gcda'文件，后续可以使用lcov工具生成
覆盖率报告。


gcno: `-ftest-coverage`选项/编译生成，包含编译的代码块和行信息。
gcda: `-fprofile-arcs`选项/运行生成，包含案例运行的轨迹信息。

## 编译选项

```
CFLAGS='-fprofile-arcs -ftest-coverage'
LDFLAGS='-fprofile-arcs -ftest-coverage'
```

## 覆盖率报告

### 全量覆盖率

通过lcov工具生成，2个步骤：


```
# 1. 产生info文件 xx.info
geninfo -o <xx.info> .

# 2. 产生html报告
genhtml --legend -o lcov-html <xx.info>
```

### 差量覆盖率

通过`lcov_cobertura.py`和`diff-cover`两个python工具生成，3个步骤：


```
# 1. 产生文件 xx.info
geninfo -o <xx.info> .

# 2. 生成xml文件
python ${LCOV_COBERTURA_DIR}/lcov_cobertura.py ./redis.info --base-dir ./src --output coverage.xml

# 3. 生成差量报告
diff-cover coverage.xml --compare-branch=origin/master --html-report report.html
```

# 内部测试

通盘考虑功能测试、内存泄露和覆盖率测试，需要做到：

- 编译时增加选项'-fprofile-arc -ftest-coverage'
- 运行时通过valgrind启动

案例的检查项目包括：

- issue测试是否符合预期
- 内存是否泄露
- issue变动是否都覆盖到

# 测试磁盘满

upredis的aof-binlog和冷热分离特性都涉及到磁盘，为了测试磁盘满时功能是否正常，
常常需要制造磁盘满的情况，以下说明常见的磁盘满测试方法。

## /dev/full

```
echo "testing" >/dev/full
```

向`/dev/full`写入总是返回磁盘满报错。可以模拟写入单文件时出现磁盘满的情况。
但是对于upredis想要随时制造(磁盘满--磁盘可写)的往复情况来说，该方法并不灵活。

## 挂载测试分区

分配较小的测试分区来模拟磁盘满。


```
1. Create a file of the size you want (here 10MB)

dd if=/dev/zero of=/home/qdii/test bs=1024 count=10000

2. Make a loopback device out of this file

losetup -f /home/qdii/test

3. Format that device in the file system you want

mkfs.ext4 /dev/loop0

4. Mount it wherever you want (/mnt/test should exist)

mount /dev/loop0 /mnt/test

5. Copy your program on that partition and test

cp /path/my/program /mnt/test && cd /mnt/test && ./program

```

参考材料: [testing out of disk space in linux](https://stackoverflow.com/questions/16044204/testing-out-of-disk-space-in-linux)


模拟(磁盘满-->磁盘空闲)的往复情况：

- 先建立100个1MB的小文件(0..99)
- 开启应用测试，直到磁盘满
- 逐个删除小文件(0..99)，可以模拟往复情况


该方案准备工作较多，但是比较接近实际生产情况。另外需要人工规划磁盘使用，难以
自动化。


## disk quota

可以通过disk quota来制造(磁盘满--磁盘可写)的往复情况。


```
$ sudo su
# useradd rkstest   # 添加quota用户，因为quota只能按照usr或group维度控制。
# edquota rkstest   # 修改quota的hard，soft配置
# edquota -t        # 修改quota的宽限时间（因为我们模拟磁盘满，因此grace时间都设置为0）
# quotaon -vaug     # 开启quota
# repquota -a       # 报告当前quota情况
# su rkstest        # 以rkstest启动应用模拟测试

```
在测试运行时可以edquota动态修改磁盘限额，模拟磁盘满和磁盘空闲。

该方案因为需要使用另外一个用户进行，因此需要拷贝测试文件，部署上稍显麻烦。


参考材料: [CHAPTER 9. IMPLEMENTING DISK QUOTAS](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/5/html/deployment_guide/ch-disk-quotas)



## 结论

开发测试阶段建议采用负载测试分区方式测试
自动化测试阶段建议采用diskquota方式测试



