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

        以上只列出了最常用的选项，其他选项参考下文,g++与gcc的选项基本相同。

## 描述

gcc分为预处理，编译，汇编，链接四个阶段。通过“阶段控制选项”可以让处理停在中间的某一阶段。比如-c选项表示不链接。

其他选项传入到特定处理阶段，有些控制预处理，有些控制编译，汇编和链接。大部分选项并没有在本文档中描述，因为这些选项的使用频率非常小。

许多选项含有多字母，因此单字母选项不能被组合在一起。比如说-d -v与-dv的含义差之千里。

大部分选项的顺序是没有影响的;但是对于同一个选项指定多次，顺序将有影响,比如-L参数。

许多选项有很长的名字，比如以-f和-W开头的，大部分这种选项都有相反含义的选项，比如说-ffoo的反义选项为-fno-foo, 本文仅说明其中不是默认选项的那个。

## 选项

以下是选项的概览，以类型归类。下面详述：

### Overall Options
           -c  -S  -E  -o file  -no-canonical-prefixes -pipe  -pass-exit-codes -x language  -v
           -###  --help[=class[,...]]  --target-help --version -wrapper @file -fplugin=file
           -fplugin-arg-name=arg -fdump-ada-spec[-slim] -fada-spec-parent=unit -fdump-go-spec=file

### C Language Options
           -ansi  -std=standard  -fgnu89-inline -aux-info filename
           -fallow-parameterless-variadic-functions -fno-asm  -fno-builtin  -fno-builtin-function
           -fhosted  -ffreestanding -fopenmp -fms-extensions -fplan9-extensions -trigraphs
           -traditional  -traditional-cpp -fallow-single-precision  -fcond-mismatch
           -flax-vector-conversions -fsigned-bitfields  -fsigned-char -funsigned-bitfields
           -funsigned-char


### Warning Options
           -fsyntax-only  -fmax-errors=n  -Wpedantic -pedantic-errors -w  -Wextra  -Wall  -Waddress
           -Waggregate-return -Waggressive-loop-optimizations -Warray-bounds -Wno-attributes
           -Wno-builtin-macro-redefined -Wc++-compat -Wc++11-compat -Wcast-align  -Wcast-qual
           -Wchar-subscripts -Wclobbered  -Wcomment -Wconversion  -Wcoverage-mismatch  -Wno-cpp
           -Wno-deprecated -Wno-deprecated-declarations -Wdisabled-optimization -Wno-div-by-zero
           -Wdouble-promotion -Wempty-body  -Wenum-compare -Wno-endif-labels -Werror  -Werror=*
           -Wfatal-errors  -Wfloat-equal  -Wformat  -Wformat=2 -Wno-format-contains-nul
           -Wno-format-extra-args -Wformat-nonliteral -Wformat-security  -Wformat-y2k
           -Wframe-larger-than=len -Wno-free-nonheap-object -Wjump-misses-init -Wignored-qualifiers
           -Wimplicit  -Wimplicit-function-declaration  -Wimplicit-int -Winit-self  -Winline
           -Wmaybe-uninitialized -Wno-int-to-pointer-cast -Wno-invalid-offsetof -Winvalid-pch
           -Wlarger-than=len  -Wunsafe-loop-optimizations -Wlogical-op -Wlong-long -Wmain
           -Wmaybe-uninitialized -Wmissing-braces  -Wmissing-field-initializers
           -Wmissing-include-dirs -Wno-mudflap -Wno-multichar  -Wnonnull  -Wno-overflow
           -Woverlength-strings  -Wpacked  -Wpacked-bitfield-compat  -Wpadded -Wparentheses
           -Wpedantic-ms-format -Wno-pedantic-ms-format -Wpointer-arith  -Wno-pointer-to-int-cast
           -Wredundant-decls  -Wno-return-local-addr -Wreturn-type  -Wsequence-point  -Wshadow
           -Wsign-compare  -Wsign-conversion  -Wsizeof-pointer-memaccess -Wstack-protector
           -Wstack-usage=len -Wstrict-aliasing -Wstrict-aliasing=n  -Wstrict-overflow
           -Wstrict-overflow=n -Wsuggest-attribute=[pure|const|noreturn|format]
           -Wmissing-format-attribute -Wswitch  -Wswitch-default  -Wswitch-enum -Wsync-nand
           -Wsystem-headers  -Wtrampolines  -Wtrigraphs  -Wtype-limits  -Wundef -Wuninitialized
           -Wunknown-pragmas  -Wno-pragmas -Wunsuffixed-float-constants  -Wunused
           -Wunused-function -Wunused-label  -Wunused-local-typedefs -Wunused-parameter
           -Wno-unused-result -Wunused-value  -Wunused-variable -Wunused-but-set-parameter
           -Wunused-but-set-variable -Wuseless-cast -Wvariadic-macros
           -Wvector-operation-performance -Wvla -Wvolatile-register-var  -Wwrite-strings
           -Wzero-as-null-pointer-constant

### Debugging Options

### Optimization Options

### Preprocessor Options
           -Aquestion=answer -A-question[=answer] -C  -dD  -dI  -dM  -dN -Dmacro[=defn]  -E  -H
           -idirafter dir -include file  -imacros file -iprefix file  -iwithprefix dir
           -iwithprefixbefore dir  -isystem dir -imultilib dir -isysroot dir -M  -MM  -MF  -MG  -MP
           -MQ  -MT  -nostdinc -P  -fdebug-cpp -ftrack-macro-expansion -fworking-directory -remap
           -trigraphs  -undef  -Umacro -Wp,option -Xpreprocessor option -no-integrated-cpp

    -M      生成预处理过程解析出来的依赖关系。
    -MM     与-M类似，但是省略系统头文件

### Assembler Option
           -Wa,option  -Xassembler option

### Linker Options
           object-file-name  -llibrary -nostartfiles  -nodefaultlibs  -nostdlib -pie -rdynamic -s
           -static -static-libgcc -static-libstdc++ -static-libasan -static-libtsan -shared
           -shared-libgcc  -symbolic -T script  -Wl,option  -Xlinker option -u symbol

### Directory Options
           -Bprefix -Idir -iplugindir=dir -iquotedir -Ldir -specs=file -I- --sysroot=dir
           --no-sysroot-suffix

### Code Generation Options


    -ansi -std=c90 -std=c++98 , c90不支持//格式的注释，因此规范中一般不建议使用//注释.
    -std=c90,c89 c99 c9x c11 c1x
    -fallow-parameterless-variadic-functions
    -fno-builtin

    -fsyntax-only
    -fmax-errors=n
    -w  Inhibit all warning messages
    -Werror Make all warnings into errors
    -Wall 
    -Wextra
    -Wformat

    Options for Debugging Your Program or GCC

    -g 
    Options That Control Optimization
    -O2
    Options Controlling the Preprocessor
    -D name
    -I dir
    Passing Options to the Assembler
    -Wa,option
    Options for Linking
     -llibrary
      -Wl,option
    
    Options for Directory Search
    -Idir
    -Ldir



