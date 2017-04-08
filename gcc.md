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

调用gcc，通常会经过预处理，编译，汇编，链接四个过程。通过“过程控制选项”可以让处理停止在中间的某一个过程。比如说，-c选项表示不运行链接。因此输出经过编译的目标文件。

其他选项都是传入到某个特定处理阶段，有些选项控制预处理，有些控制编译，其他的控制汇编和链接。大部分选项并没有在本文档中描述，因为这些选项的使用频率非常小。

大部分gcc选项对于c程序来说非常重要，对于那些语言相关的选项，本文将明确指出,否则该选项对于所有语言均相同。

gcc接受选项和文件参数。许多选项含有多字母，因此单字母选项不能被组合在一起。比如说-d -v 与 -dv的含义差之千里。

大部分选项的顺序是没有影响的，但是对于同一个选项指定多次，顺序将有影响。比如，多次制定-L参数，文件家的顺序和声明的顺序相同。

许多选项有很长的名字，比如以-f和-W开头的，大部分这种选项都有相反含义的选项，比如说-ffoo的反义选项为-fno-foo, 本文仅说明其中不是默认选项的那个。

## 选项

###选项概述

以下是选项的概览，以类型归类。下面详述：

      Overall Options
           -c  -S  -E  -o file  -no-canonical-prefixes -pipe  -pass-exit-codes -x language  -v
           -###  --help[=class[,...]]  --target-help --version -wrapper @file -fplugin=file
           -fplugin-arg-name=arg -fdump-ada-spec[-slim] -fada-spec-parent=unit -fdump-go-spec=file

       C Language Options
           -ansi  -std=standard  -fgnu89-inline -aux-info filename
           -fallow-parameterless-variadic-functions -fno-asm  -fno-builtin  -fno-builtin-function
           -fhosted  -ffreestanding -fopenmp -fms-extensions -fplan9-extensions -trigraphs
           -traditional  -traditional-cpp -fallow-single-precision  -fcond-mismatch
           -flax-vector-conversions -fsigned-bitfields  -fsigned-char -funsigned-bitfields
           -funsigned-char


       C++ Language Options
           -fabi-version=n  -fno-access-control  -fcheck-new -fconstexpr-depth=n
           -ffriend-injection -fno-elide-constructors -fno-enforce-eh-specs -ffor-scope
           -fno-for-scope  -fno-gnu-keywords -fno-implicit-templates -fno-implicit-inline-templates
           -fno-implement-inlines  -fms-extensions -fno-nonansi-builtins  -fnothrow-opt
           -fno-operator-names -fno-optional-diags  -fpermissive -fno-pretty-templates -frepo
           -fno-rtti  -fstats  -ftemplate-backtrace-limit=n -ftemplate-depth=n
           -fno-threadsafe-statics -fuse-cxa-atexit  -fno-weak  -nostdinc++ -fno-default-inline
           -fvisibility-inlines-hidden -fvisibility-ms-compat -fext-numeric-literals -Wabi
           -Wconversion-null  -Wctor-dtor-privacy -Wdelete-non-virtual-dtor -Wliteral-suffix
           -Wnarrowing -Wnoexcept -Wnon-virtual-dtor  -Wreorder -Weffc++  -Wstrict-null-sentinel
           -Wno-non-template-friend  -Wold-style-cast -Woverloaded-virtual  -Wno-pmf-conversions
           -Wsign-promo

       Objective-C and Objective-C++ Language Options
           -fconstant-string-class=class-name -fgnu-runtime  -fnext-runtime -fno-nil-receivers
           -fobjc-abi-version=n -fobjc-call-cxx-cdtors -fobjc-direct-dispatch -fobjc-exceptions
           -fobjc-gc -fobjc-nilcheck -fobjc-std=objc1 -freplace-objc-classes -fzero-link -gen-decls
           -Wassign-intercept -Wno-protocol  -Wselector -Wstrict-selector-match
           -Wundeclared-selector

       Language Independent Options
           -fmessage-length=n -fdiagnostics-show-location=[once|every-line]
           -fno-diagnostics-show-option -fno-diagnostics-show-caret

       Warning Options
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

       Debugging Options
           -dletters  -dumpspecs  -dumpmachine  -dumpversion -fsanitize=style -fdbg-cnt-list
           -fdbg-cnt=counter-value-list -fdisable-ipa-pass_name -fdisable-rtl-pass_name
           -fdisable-rtl-pass-name=range-list -fdisable-tree-pass_name -fdisable-tree-pass-
           name=range-list -fdump-noaddr -fdump-unnumbered -fdump-unnumbered-links
           -fdump-translation-unit[-n] -fdump-class-hierarchy[-n] -fdump-ipa-all -fdump-ipa-cgraph
           -fdump-ipa-inline -fdump-passes -fdump-statistics -fdump-tree-all
           -fdump-tree-original[-n] -fdump-tree-optimized[-n] -fdump-tree-cfg -fdump-tree-alias
           -fdump-tree-ch -fdump-tree-ssa[-n] -fdump-tree-pre[-n] -fdump-tree-ccp[-n]
           -fdump-tree-dce[-n] -fdump-tree-gimple[-raw] -fdump-tree-mudflap[-n] -fdump-tree-dom[-n]
           -fdump-tree-dse[-n] -fdump-tree-phiprop[-n] -fdump-tree-phiopt[-n]
           -fdump-tree-forwprop[-n] -fdump-tree-copyrename[-n] -fdump-tree-nrv -fdump-tree-vect
           -fdump-tree-sink -fdump-tree-sra[-n] -fdump-tree-forwprop[-n] -fdump-tree-fre[-n]
           -fdump-tree-vrp[-n] -ftree-vectorizer-verbose=n -fdump-tree-storeccp[-n]
           -fdump-final-insns=file -fcompare-debug[=opts]  -fcompare-debug-second
           -feliminate-dwarf2-dups -fno-eliminate-unused-debug-types
           -feliminate-unused-debug-symbols -femit-class-debug-always -fenable-kind-pass
           -fenable-kind-pass=range-list -fdebug-types-section -fmem-report-wpa -fmem-report
           -fpre-ipa-mem-report -fpost-ipa-mem-report -fprofile-arcs -fopt-info
           -fopt-info-options[=file] -frandom-seed=string -fsched-verbose=n -fsel-sched-verbose
           -fsel-sched-dump-cfg -fsel-sched-pipelining-verbose -fstack-usage  -ftest-coverage
           -ftime-report -fvar-tracking -fvar-tracking-assignments
           -fvar-tracking-assignments-toggle -g  -glevel  -gtoggle  -gcoff  -gdwarf-version -ggdb
           -grecord-gcc-switches  -gno-record-gcc-switches -gstabs  -gstabs+  -gstrict-dwarf
           -gno-strict-dwarf -gvms  -gxcoff  -gxcoff+ -fno-merge-debug-strings -fno-dwarf2-cfi-asm
           -fdebug-prefix-map=old=new -femit-struct-debug-baseonly -femit-struct-debug-reduced
           -femit-struct-debug-detailed[=spec-list] -p  -pg  -print-file-name=library
           -print-libgcc-file-name -print-multi-directory  -print-multi-lib
           -print-multi-os-directory -print-prog-name=program  -print-search-dirs  -Q
           -print-sysroot -print-sysroot-headers-suffix -save-temps -save-temps=cwd -save-temps=obj
           -time[=file]

    Optimization Options
           -faggressive-loop-optimizations -falign-functions[=n] -falign-jumps[=n]
           -falign-labels[=n] -falign-loops[=n] -fassociative-math -fauto-inc-dec
           -fbranch-probabilities -fbranch-target-load-optimize -fbranch-target-load-optimize2
           -fbtr-bb-exclusive -fcaller-saves -fcheck-data-deps -fcombine-stack-adjustments
           -fconserve-stack -fcompare-elim -fcprop-registers -fcrossjumping -fcse-follow-jumps
           -fcse-skip-blocks -fcx-fortran-rules -fcx-limited-range -fdata-sections -fdce
           -fdelayed-branch -fdelete-null-pointer-checks -fdevirtualize -fdse -fearly-inlining
           -fipa-sra -fexpensive-optimizations -ffat-lto-objects -ffast-math -ffinite-math-only
           -ffloat-store -fexcess-precision=style -fforward-propagate -ffp-contract=style
           -ffunction-sections -fgcse -fgcse-after-reload -fgcse-las -fgcse-lm -fgraphite-identity
           -fgcse-sm -fhoist-adjacent-loads -fif-conversion -fif-conversion2 -findirect-inlining
           -finline-functions -finline-functions-called-once -finline-limit=n
           -finline-small-functions -fipa-cp -fipa-cp-clone -fipa-pta -fipa-profile
           -fipa-pure-const -fipa-reference -fira-algorithm=algorithm -fira-region=region
           -fira-hoist-pressure -fira-loop-pressure -fno-ira-share-save-slots
           -fno-ira-share-spill-slots -fira-verbose=n -fivopts -fkeep-inline-functions
           -fkeep-static-consts -floop-block -floop-interchange -floop-strip-mine
           -floop-nest-optimize -floop-parallelize-all -flto -flto-compression-level
           -flto-partition=alg -flto-report -fmerge-all-constants -fmerge-constants -fmodulo-sched
           -fmodulo-sched-allow-regmoves -fmove-loop-invariants fmudflap -fmudflapir -fmudflapth
           -fno-branch-count-reg -fno-default-inline -fno-defer-pop -fno-function-cse
           -fno-guess-branch-probability -fno-inline -fno-math-errno -fno-peephole -fno-peephole2
           -fno-sched-interblock -fno-sched-spec -fno-signed-zeros -fno-toplevel-reorder
           -fno-trapping-math -fno-zero-initialized-in-bss -fomit-frame-pointer
           -foptimize-register-move -foptimize-sibling-calls -fpartial-inlining -fpeel-loops
           -fpredictive-commoning -fprefetch-loop-arrays -fprofile-report -fprofile-correction
           -fprofile-dir=path -fprofile-generate -fprofile-generate=path -fprofile-use
           -fprofile-use=path -fprofile-values -freciprocal-math -free -fregmove -frename-registers
           -freorder-blocks -freorder-blocks-and-partition -freorder-functions
           -frerun-cse-after-loop -freschedule-modulo-scheduled-loops -frounding-math
           -fsched2-use-superblocks -fsched-pressure -fsched-spec-load -fsched-spec-load-dangerous
           -fsched-stalled-insns-dep[=n] -fsched-stalled-insns[=n] -fsched-group-heuristic
           -fsched-critical-path-heuristic -fsched-spec-insn-heuristic -fsched-rank-heuristic
           -fsched-last-insn-heuristic -fsched-dep-count-heuristic -fschedule-insns
           -fschedule-insns2 -fsection-anchors -fselective-scheduling -fselective-scheduling2
           -fsel-sched-pipelining -fsel-sched-pipelining-outer-loops -fshrink-wrap -fsignaling-nans
           -fsingle-precision-constant -fsplit-ivs-in-unroller -fsplit-wide-types -fstack-protector
           -fstack-protector-all -fstrict-aliasing -fstrict-overflow -fthread-jumps -ftracer
           -ftree-bit-ccp -ftree-builtin-call-dce -ftree-ccp -ftree-ch -ftree-coalesce-inline-vars
           -ftree-coalesce-vars -ftree-copy-prop -ftree-copyrename -ftree-dce -ftree-dominator-opts
           -ftree-dse -ftree-forwprop -ftree-fre -ftree-loop-if-convert
           -ftree-loop-if-convert-stores -ftree-loop-im -ftree-phiprop -ftree-loop-distribution
           -ftree-loop-distribute-patterns -ftree-loop-ivcanon -ftree-loop-linear
           -ftree-loop-optimize -ftree-parallelize-loops=n -ftree-pre -ftree-partial-pre -ftree-pta
           -ftree-reassoc -ftree-sink -ftree-slsr -ftree-sra -ftree-switch-conversion
           -ftree-tail-merge -ftree-ter -ftree-vect-loop-version -ftree-vectorize -ftree-vrp
           -funit-at-a-time -funroll-all-loops -funroll-loops -funsafe-loop-optimizations
           -funsafe-math-optimizations -funswitch-loops -fvariable-expansion-in-unroller
           -fvect-cost-model -fvpt -fweb -fwhole-program -fwpa -fuse-ld=linker -fuse-linker-plugin
           --param name=value -O  -O0  -O1  -O2  -O3  -Os -Ofast -Og

       Preprocessor Options
           -Aquestion=answer -A-question[=answer] -C  -dD  -dI  -dM  -dN -Dmacro[=defn]  -E  -H
           -idirafter dir -include file  -imacros file -iprefix file  -iwithprefix dir
           -iwithprefixbefore dir  -isystem dir -imultilib dir -isysroot dir -M  -MM  -MF  -MG  -MP
           -MQ  -MT  -nostdinc -P  -fdebug-cpp -ftrack-macro-expansion -fworking-directory -remap
           -trigraphs  -undef  -Umacro -Wp,option -Xpreprocessor option -no-integrated-cpp

       Assembler Option
           -Wa,option  -Xassembler option

       Linker Options
           object-file-name  -llibrary -nostartfiles  -nodefaultlibs  -nostdlib -pie -rdynamic -s
           -static -static-libgcc -static-libstdc++ -static-libasan -static-libtsan -shared
           -shared-libgcc  -symbolic -T script  -Wl,option  -Xlinker option -u symbol

       Directory Options
           -Bprefix -Idir -iplugindir=dir -iquotedir -Ldir -specs=file -I- --sysroot=dir
           --no-sysroot-suffix

      Code Generation Options
           -fcall-saved-reg  -fcall-used-reg -ffixed-reg  -fexceptions -fnon-call-exceptions
           -fdelete-dead-exceptions  -funwind-tables -fasynchronous-unwind-tables -fno-gnu-unique
           -finhibit-size-directive  -finstrument-functions
           -finstrument-functions-exclude-function-list=sym,sym,...
           -finstrument-functions-exclude-file-list=file,file,...  -fno-common  -fno-ident
           -fpcc-struct-return  -fpic  -fPIC -fpie -fPIE -fno-jump-tables -frecord-gcc-switches
           -freg-struct-return  -fshort-enums -fshort-double  -fshort-wchar -fverbose-asm
           -fpack-struct[=n]  -fstack-check -fstack-limit-register=reg  -fstack-limit-symbol=sym
           -fno-stack-limit -fsplit-stack -fleading-underscore  -ftls-model=model
           -fstack-reuse=reuse_level -ftrapv  -fwrapv  -fbounds-check -fvisibility
           -fstrict-volatile-bitfields -fsync-libcalls



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

