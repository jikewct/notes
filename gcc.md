# gcc

gcc - GNU c c++ 编译器

## 语法

    gcc [-c|-S|-E] [-std=<standard>]
        [-g] [-pg] [-Olevel]
        [-Wwarn..] [-Wpedantic]
        [-Idir...] [-Ldir...]
        [-Dmarcro[=defn]...] [-Umacro]
        [-foption...] [-mmachine-option...]
        [-o outputfile] [@file] infile..

## 描述

- gcc分为预处理，编译，汇编，链接四个阶段。通过“阶段控制选项”可以让处理停在中间的某一阶段
- 许多选项含有多字母，因此单字母选项不能被组合在一起。比如说-d -v与-dv的含义差之千里
- 大部分选项的顺序是没有影响的；但是对于同一个选项指定多次，顺序将有影响,比如-L参数
- 大部分-f和-W开头的选项都有相反含义的选项，比如说-ffoo的反义选项为-fno-foo

## 选项


### Overall Options

-   -E              stop after preprocess

### C Language Options

### Warning Options

    -w              Inhibit all warning messages
    -Werror         Make all warnings into errors
    -Wall 

### Debugging Options

### Optimization Options

-   -g 

### Preprocessor Options

-   -M              生成预处理过程解析出来的依赖关系。
-   -MM             与-M类似，但是省略系统头文件
-   -D              define macro

### Assembler Option

### Linker Options

-   -Wl,option      pass option to linker
-   --gc-sections   clean unused input sections
-   -Map=mapfile    print a link map to mapfile   

### Directory Options

    -Idir
    -Ldir

### Code Generation Options

-   -ansi       ansi c code 
-   -std=c90    c89 c99 c9x c11 c1x


## related

- [pikoRT](pikoRT.html)
- [ucore](ucore.html)
