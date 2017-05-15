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

