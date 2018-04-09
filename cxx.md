# c++11

- shared_ptr

实现原理：参考https://stackoverflow.com/questions/9200664/how-is-the-stdtr1shared-ptr-implemented
简单讲:
- shared_ptr包含两个指针，一个是指向Object的指针，另一个指向refcount
- 每次shared_ptr ctor,copy,assign,dtor,reset时进行相应的refcount增减
- 在refcount == 0时，delete Object

使用方法：
- 因为在引用计数，所以shared_ptr一般是栈变量（栈内存释放时引用计数减少）
- https://stackoverflow.com/questions/29643974/using-stdmove-with-stdshared-ptr
- std::make_shared比ctor(rawptr)更加高效，因为make_shared可以把refcount和object一次就malloc出来

- unique_ptr

原理与使用和shared_ptr类似，有一点比较常用的是由于unique

- std::move

std::move就是一个cast，将左值cast为右值，从而触发move ctor/assign

- 构造函数初始化列表
以下必须使用初始化列表：
 > const成员
 > 没有默认ctor的成员


- vector.push_back(T& t)

push_back操作将执行拷贝（因为vector不知道t的生命周期）；
我觉得push_back可以采用以下两种策略：
A. pass by value then move
B. pass by ref then copy
第一种与rvalue一样。

对于一个class/struct 传递的时候不应该传值！应该传递引用或者（智能）指针；
对于一个class/struct 返回的时候不应该传值！应该传递引用或者（智能）指针；


- cast
    - static_cast，与C语言的cast类似，但是会检查类型的相关性（upcast, downcast)
    - reinterpret_cast直接将二进制重新reinterpret（没有转换）
    - const_cast，C语言无法做到的操作：将const 转换为non const
    - dynamic_cast, 用于执行“安全的downcast"，有性能问题！



