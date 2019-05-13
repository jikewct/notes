# Makefile

## random notes

- 变量声明

变量声明分为:

1) Lazy Set ('=')

使用时递归解析

2) Immediate Set (':=')

声明时解析

3) Set If Absent ('?=')

不存在时，与'='相同，否则没有动作。

4) Append ('+=')

追加，展开方式与定义时相同，如果没有定义则和'='相同，比如:


```
LDFLAGS = -lz
LDFLAGS += -l$(LIB1)

LIB1 = lib1
```

展开之后LDFLAGS结果为 -lz -llib1，但如果LDFLAGS定义时为 ':='，那么结果为 -lz -l。


https://stackoverflow.com/questions/448910/what-is-the-difference-between-the-gnu-makefile-variable-assignments-a

- 特殊符号
 $@ 输出文件名; @^ 所有依赖; @< 第一个依赖;

- include   
与c语言include类似, -include不存在等错误

- suffix rule 
    已经由pattern rule代替,但仍然兼容.
    分为两种：single suffix rule(e.g. .c) & double suffix rule(e.g. .c.o)
    .c .o在默认的suffixes中，.SUFFIXES : .c .o .xo .so 指明.xo .so等suffix
    举例如下:
    .c.o:
        $(CC) -c $(CFLAGS) -o $@ $<

- gmake & make
gmake特指GNU implemented make, make 指系统默认make。
大多数linux中make默认是gmake， bsd中的是bsd make，其他的商业unix中使用的可能是其他make。

- multiple rule for one target
多个prerequisite合并，多个receipt报错, 典型示例如下：
objects = foo.o bar.o
foo.o : defs.h
bar.o : defs.h test.h
$(objects) : config.h

- antirez/redis Makefile 风格
gcc -MM \*.c 动生成依赖关系;
suffix rule (.c.o) 声明.o依赖的.c;
bin: a.o b.o

- OBJS += $(SSRC:.S=.o) $(CSRC:.c=.o) 表示substitution refs

https://www.gnu.org/software/make/manual/html_node/Substitution-Refs.html

- Makefile变量优先级

变量可以分为三类:env,file,cmd：

env:    相当于make解析Makefile之前已经生成了envvar=value的定义。最先执行，优先级最低
file:   解析Makefile，按照`:=(expand)`, `=(lazy expand)`, `+=(append)`, `?=(set if not exists)`进行变量展开
cmd:    命令行中传入的变量直接覆盖file中的定义，(但env还是有效)


注意以下传入参数的方式：


```
# CFLAGS as env
CFLAGS=xxx make

# CFLAGS as cmd
make CFLAGS=xxx

```

- 特殊变量

```
MAKECMDGOALS
CURDIR
```

- 函数

```
shell
foreach
filter
wildcard
join
dir
patsubst

info
warning
error
```

- FORCE

如果一个goal不依赖于任何文件，那么每次执行该goal都会执行, 也就是FORCE效果。

## best practice


```

# 按照范式来，CFLAGS等环境变量都应该继承
CLEAN_FILES = # deliberately empty, so we can append below.
CFLAGS += ${EXTRA_CFLAGS}
CXXFLAGS += ${EXTRA_CXXFLAGS}
LDFLAGS += $(EXTRA_LDFLAGS)
MACHINE ?= $(shell uname -m)
ARFLAGS = ${EXTRA_ARFLAGS} rs
STRIPFLAGS = -S -x

DEBUG_LEVEL?=1
OPT= -O2 -fno-omit-frame-pointer -DNDEBUG

# make V=1 切换显示编译过程摘要和细节宏
AM_DEFAULT_VERBOSITY = 0

AM_V_GEN = $(am__v_GEN_$(V))
am__v_GEN_ = $(am__v_GEN_$(AM_DEFAULT_VERBOSITY))
am__v_GEN_0 = @echo "  GEN     " $@;
am__v_GEN_1 =
AM_V_at = $(am__v_at_$(V))
am__v_at_ = $(am__v_at_$(AM_DEFAULT_VERBOSITY))
am__v_at_0 = @
am__v_at_1 =

AM_V_CC = $(am__v_CC_$(V))
am__v_CC_ = $(am__v_CC_$(AM_DEFAULT_VERBOSITY))
am__v_CC_0 = @echo "  CC      " $@;
am__v_CC_1 =
CCLD = $(CC)
LINK = $(CCLD) $(AM_CFLAGS) $(CFLAGS) $(AM_LDFLAGS) $(LDFLAGS) -o $@
AM_V_CCLD = $(am__v_CCLD_$(V))
am__v_CCLD_ = $(am__v_CCLD_$(AM_DEFAULT_VERBOSITY))
am__v_CCLD_0 = @echo "  CCLD    " $@;
am__v_CCLD_1 =
AM_V_AR = $(am__v_AR_$(V))
am__v_AR_ = $(am__v_AR_$(AM_DEFAULT_VERBOSITY))
am__v_AR_0 = @echo "  AR      " $@;
am__v_AR_1 =


# 解析Makefile过程执行脚本的方法
dummy := $(shell (export ROCKSDB_ROOT="$(CURDIR)"; export PORTABLE="$(PORTABLE)"; "$(CURDIR)/build_tools/build_detect_platform" "$(CURDIR)/make_config.mk"))

# so符号链接创建


```

## FLAGS


- CFLAGS

CFLAGS += $(WARNING_FLAGS) -I. -I./include $(PLATFORM_CCFLAGS) $(OPT)

STD

WARN = -W -Wextra -Wall -Wsign-compare -Wshadow -Wunused-parameter -Werror

OPT

DEBUG

COVERAGEFLAGS

- LDFLAGS

- LIBS

- SHARED_CFLAGS

- SHARED_LDFLAGS

-Wl,--no-as-needed -shared -Wl,-soname -Wl,

- EXEC_LDFLAGS

- ARFLAGS



```


- 生成.d文件

```
%.cc.d: %.cc
	@$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) \
	  -MM -MT'$@' -MT'$(<:.cc=.o)' "$<" -o '$@'
```


# autotools

## 可移植性

解决一下可移植性问题：

- strtod在某些平台不存在
- strchr在某些平台名字为index
- setprgp函数原型不同
- malloc(0)的行为不同
- pow所在的so不同(libm.so,libc.so)
- 头文件不同(string.h, strings.h, memory.h)

## 发展历史

最早1991年出现configure脚本，做到根据当前系统环境产生config.h (#define)和Makefile


## 标准目标

```
make all 编译
make clean 清除编译产物
make check 回归测试
make install 安装
make distclean 清除configure产物
make dist 产生tarball
```
## 标准宏

```
CC c编译器
CFLAGS c编译器flags
CXX c++编译器
CXXFLAGS c++编译器flags
LDFLAGS 链接flags
CPPFLAGS 预编译器flags
LIBS 
LDADD
LIBADD
```
## 组件

```
autoconf
---
autoconf configure.ac --> configure
autoheader configure.ac --> config.h.in 
autoreconf 组合各种autotools
autoscan scan --> configure.scan
autoupdate update configure.ac obselete macros
ifnames 从#if/#ifdef中获取信息
autom4te m4宏替换引擎

automake
---
automake configure.ac+makefile.am --> makefile.in
aclocal 扫描configure.ac，并且从第三方组件中拷贝到aclocal.m4

```

libtool 采用LibtoolArchive(.la)来抽象各种so库
gettext 解决i18n,l10n问题

## 宏

```
AC_* AutoConf *
AM_* AutoMake *


AC_INIT(PACKAGE, VERSION, BUG-REPORT-ADDRESS)
AC_PREREQ(VERSION)
AM_INIT_AUTOMAKE
AC_CONFIG_AUX_DIR(DIRECTORY) install-sh decomp等辅助脚本的存放位置
AC_PROG_CC 检查CC
AC_CONFIG_HEADERS 定义autoheader输出
AC_CONFIG_FILES 定义automake输出
AC_OUTPUT 实际生成所有输出
```


# cmake

cmake - 跨平台Makefile生成器

语法

    cmake [options] <path-to-source>
    cmake [options] <path-to-existing-build>

描述  
    
    项目通过-D进行自定义设置, -i 选项将使用交互选择模式。

选项
    
    -C <initial-cache>
        
        预加载缓存

    -D <var>:<type>=<value>
        
        创建cmake 缓存条目

    -U  <globbing_expr>

        删除匹配globbing_expr的条目

    -G  <generator-name>
        
        指定构建系统名称

    -Wno-dev
        
        不输出开发者警示

    -Wdev
        
        开启开发者警示

    -E  Cmake command mode
        
        为了真正的平台无关，CMake提供了一些平台无关的命令。使用-E能够获得使用帮助,可用的命令
        chdir， compare_files, copy, copy_directory, copy_if_different, echo, echo_append,
        environment, make_directory, md5sum, remove, remove_directory, rename, tar, time,
        touch, touch_nocreate。

    --build <dir> 

        编译代码。

    -N  view mode only 

    -P  process script only

    --find-package
        
        使用cmkae查找系统包

    --graphviz=[file]

        生成依赖graphviz图

    --system-information [file]
    
        dump系统信息

    --debug-output cmake调试模式

    --trace cmake trace 模式

    --warn-uninitialized 警告未初始化变量

    --warn-unused-vars 警告未使用变量

    --help-command cmd [file] 打印cmd命令的帮助

    --help-command-list 打印可用命令

    --help-commands 打印所有命令的帮助

    --help-compatcommand 打印兼容性命令

    --help-module module 打印模块帮助

    --help-module-list 列出所有模块

    --help-modules 打印所有模块帮助
    
    --help-custom-modules 打印所有自定义模块的帮助

    --help-policy cmp policy帮助

    --help-policies

    --help-property prop [file] 打印属性帮助

    --help-property-list

    --help-properties

    --help-variable var 打印变量帮助

    --help-variable-list

    --help-variables

    --help, -help ,-usage , -h, -H, /? 打印帮助

    --help-full

    --help-html

    --help-man
 
## macros

    CMAKE_BUILD_TYPE
    CMAKE_SOURCE_DIR
    CMAKE_MODULE_PATH
    CMAKE_C_FLAGS_REALEASE
    CMAKE_C_FLAGS_DEBUG
    CMAKE_SKIP_BUILD_RPATH
    CMAKE_SKIP_INSTALL_RPATH
    CMAKE_SYSTEM_NAME
    CMAKE_SHARD_LINKER_FLAGS
    CMAKE_PROJECT_NAME
    CMAKE_POLICY
    CMAKE_BINARY_DIR
    CMAKE_CXX_FLAGS_COVERAGE
    CMAKE_CXX_FLAGS_DEBUG
    CMAKE_COMMAND
    CMAKE_INSTALL_PREFIX
    CMAKE_PARSE_ARGUMENT


## so

so name          lib<xxx>.so.x
real name        lib<xxx>.so.x.y[.z]
linker name      lib<xxx>.so

- 程序依赖使用的是soname
- 我们只创建real name
- 安装完real name之后，执行ldconfig可自动创建so name，但不会创建linker name
- 在编译阶段，通常创建一个linker name软链接，指向so name或者real name

http://tldp.org/HOWTO/Program-Library-HOWTO/shared-libraries.html


