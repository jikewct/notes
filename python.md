#python

* args kwargs

args: 类似于c语言的va_list, 但是args的类型是tuple
kwargs: keyword args

args必须在kwargs前

* @ decorator

* assert 语法： assert condition, hint (when fail)

* import 语法：

import的搜索路径? sys.path
site-packge是什么意思？ 一般是自己安装的包的默认路径
如何安装一个第三方包？ pip setup
import几种不同方式？ import; from a import b as c;


* 对象模型

 class A(B):

    class_property_a
    class_property_b

    def __init__(self, x, y, z):
        self.object_property_x = x
        self.object_property_y = y
        self.object_property_z = z

    def class_method(arga, argb):
        pass

    def object_method(self, arga, argb):
        pass

 与c#很大不同的是：
    1. 在类空间声明的是类属性：类似于c#的static;
    2. 对象属性不声明，直接self.object_property_x进行动态添加！
    3. 对象属性只能在__init__中添加
    4. 带有self的对向方法，不带self的是类方法


* python的dict的key可以是tuple吗？

可以, immutable可以作为key；tuple就是immutable

* python的tuple怎么get

  tup1 = ('k1','k2')
  assert 'k1' == tup1[0]
  assert 'k2' == tup1[1]

* 循环

python没有foreach

for k in list:
for k,v in list.iteritems(): # python 2.x
for k,v in list.items(): # python 3.x


* python debug

python -m pdb <xxx.py>

* 字符串

1. 格式化语法与c printf语法类似: 'my name is %s and weight is %d kg' % ('srzhao', 70)
2. 判断是否为空 str.isspace()
3. 转换为数字 int('1'), fload('1.0')

* python-操作符
三元操作符: x if con_true else y

* python数据结构-dict

dict的key可以是不同类型

* python数据结构-str

* nosetests debug

为什么nosetests需要进行debug？
主要是因为nosetests是一个框架，如果python -m pdb <test_cases.py>
则不会运行到 setup, teardown, test_xx等函数, 因此需要nosetests
支持pdb调试。

如何对nosetests进行debug，主要参考资料：man nosetests

--pdb pdb on error
--pdb-failures pdb on failures

另外如果可以在程序中设断点
A) 使用-s选项让nose不capture stdout 然后：
import pdb; pdb.set_trace() 
B) from nose.tools import set_trace; set_trace() # 该函数会自动设置stdout

* nosetests 日志输出

nosetests --logging-level=INFO

* ctypes

1. load so

cdll使用cdecl调用范式，windll使用stdcall范式, oledll使用stdcall范式且预期返回HRESULT。
linux上使用：
from ctypes import *
cdll.LoadLibrary('libxx.so')

2. acess functions

基本上linux上的calling convention问cdecl，而类似kernel32.GetModuleHandleA
之类的WINDOWS函数为stdcall类型。

print libxx.<func>

3. ctypes类型对应

| ctypes type | C type                                 | Python type                |
| ---         | ---                                    | ---                        |
| c_char      | char                                   | 1-character string         |
| c_wchar     | wchar_t                                | 1-character unicode string |
| c_byte      | char                                   | int/long                   |
| c_ubyte     | unsigned char                          | int/long                   |
| c_short     | short                                  | int/long                   |
| c_ushort    | unsigned short                         | int/long                   |
| c_int       | int                                    | int/long                   |
| c_uint      | unsigned int                           | int/long                   |
| c_long      | long                                   | int/long                   |
| c_ulong     | unsigned long                          | int/long                   |
| c_longlong  | __int64 or long long                   | int/long                   |
| c_ulonglong | unsigned __int64 or unsigned long long | int/long                   |
| c_float     | float                                  | float                      |
| c_double    | double                                 | float                      |
| c_char_p    | char * (NUL terminated)                | string or None             |
| c_wchar_p   | wchar_t * (NUL terminated)             | unicode or None            |
| c_void_p    | void *                                 | int/long or None           |


* python ord() chr() unichr()
