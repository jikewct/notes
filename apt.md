# apt

## 整体架构
常用的包管理工具包含三类：dpkg，apt，aptitude。

dpkg主要对本地软件包进行管理。

apt包含多个相关工具:apt apt-get apt-cache apt-config apt\_preference

    apt 包管理命令行
    apt-get 包管理后端工具，负责包的在线安装和升级
    apt-cache apt cache查询工具, 查询软件包的状态和依赖关系
    apt-file 查询软件包的信息
    apt-config apt 配置查询工具

aptitude是更加高层的包管理工具，包含文本界面和命令行两种使用方式。


## 常用的操作

1. 列出软件包包含文件 dkpg -L <pkg>
2. 列出所有安装的软件包 dpkg -l 
3. 查看文件所属的软件包 dpkg -S <pkg>
4. 查看软件包是否已安装 dpkg -s <pkg>
