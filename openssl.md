# openssl

redhat openssl的特殊之处：redhat根据美国法律定制了一个openssl包。
为什么不用autoconf：因为cmake，autoconf不能支持openssl支持的全部平台。


## 编译架构

./config - 根据平台猜测参数，并调用Configure的脚本; config -t 可以看到猜测结果
./Configure

1. 产生makefile
每次Configure产生一个Makefile.new: 以Makefile为模板，根据Configure中采集的参数生成
如果重新配置或者两次Makefile不一样，Makefile被分为Makefile.bak；Makefile.new替换Makefile;
否则直接删除Makefile.new


2. 生成<crypto/opensslconf.h.in>
思路与Makefile类似： 以老的conf为模板，根据本次配置生成conf.new； 对比两者的区别，如果不同则备份old，替换为new；


3. make xxxx
config在生成Makefile之后，会执行 make PERL='/usr/bin/perl' links gentests 正是该命令对后面的测试案例造成了影响。

4. dofile
思路还是与之前的类似，根据template，然后对文件的内容进行编辑替换，然后输出根据配置生成的新文件。

具体就是替换了tools/c_rehash中的perl路径，my $dir, my $prefix的值；替换了apps/CA.pl中的perl路径。

- 如何对make test产生影响

生成了新Makefile之后，调用了 make links gentests，因此分析了这个过程就可以阻止生成非必要的测试案例。

    - links
    执行以下脚本
        - util/mkdir-p.pl include/openssl
        因为有些平台mkdir不支持-p参数，该命令就是mkdir -p
        - util/mklink.pl include/openssl
        先删除include/openssl中已经存在的symlink，然后重新建立file=>include/openssl/file到xxx的链接
        - 递归make links
        set -e; 
        target=links;
        for dir in "crypto ssl engines apps test tools"; do 
            if [-d $dir];then
                (cd $dir && 
                echo makding links in $dir... &&
                $(CLEARENV) &&
                $(MAKE) -e $(BUILDENV) TOP=../ DIR=$dir links) ||
                exit 1;
             fi;
         done

         $(BUILDENV)表示的传递给make的所有flags

    so，每层的Makefile将所在文件夹的文件建立链接

    - gentests

    cd test &&
    $(CLEARENV) &&
    make -e $(BUILDENV) TESTS=alltests OPENSS_DEBUG_MEMORY=on generate;

    test/Makefile中的generate目标：
    generate: $(SRC)
    $(SRC):
        @sh util/point.sh dummytest.c $@

    - 利用了Multiple target规则，所以所有列表中的文件如果不存在都会连接到dummy
    - 这个Makefile规则利用了文件如果存在的话，那么就不会执行rule的特性。

    当前以下文件dummy
```
lrwxrwxrwx.  1 srzhao srzhao    11 Nov  6 11:21 jpaketest.c -> dummytest.c
lrwxrwxrwx.  1 srzhao srzhao    11 Nov  6 11:21 md2test.c -> dummytest.c
lrwxrwxrwx.  1 srzhao srzhao    11 Nov  6 11:21 rc5test.c -> dummytest.c
```

- 如何不生成特定的test

    - crypto:
    TEST=constant_time_test.c
    crypto目录下的以下文件夹将会被递归执行make links，到时SDIRS会被Configure文件修改
    SDIRS=  \
        objects \
        md4 md5 sha mdc2 hmac ripemd whrlpool \
        des aes rc2 rc4 idea bf cast camellia seed modes \
        bn ec rsa dsa ecdsa dh ecdh dso engine \
        buffer bio stack lhash rand err \
        evp asn1 pem x509 x509v3 conf txt_db pkcs7 pkcs12 comp ocsp ui krb5 \
        cms pqueue ts srp cmac
    - ssl
    TEST=ssltest.c heartbeat_test.c clienthellotest.c sslv2conftest.c dtlstest.c bad_dtls_test.c
    - engines
        - ccgost
        (nil)
    - apps
        (nil)
    - test
        (nil)
    - tools
        (nil)


## 引入gmssl

- 基线版本上游发布版-1.0.2K
基线版本1.0.2K编译，测试通过

- gm 分支从1.0.2K开发，并且已经可以合并

## 引入rhel的修改

rhel为了适应美国的法律，对openssl进行了定制化，具体包括如下：

FIBS - federal information processing standart, 联邦牛逼

一共50个patch

修改：

### hobble （砍掉一部分）

- 砍掉crypto下的srp/*.c(但不包括test)，bn/*gf2m.c，ec/{ec2*.c,ec_curve.c, ecp_nistp22?.c, ectest.c} 
- 将crypto ssl apps test文件夹中.h头文件中关于SRP，EC2M的引用去除。
- 将ec_curve.c和ectest.c拷贝到crypto/ec/文件夹中。

### 应用patch

#### build changes

Patch1: openssl-1.0.2e-rpmbuild.patch
Patch2: openssl-1.0.2a-defaults.patch
Patch4: openssl-1.0.2i-enginesdir.patch
Patch5: openssl-1.0.2a-no-rpath.patch
Patch6: openssl-1.0.2a-test-use-localhost.patch
Patch7: openssl-1.0.0-timezone.patch
Patch8: openssl-1.0.1c-perlfind.patch
Patch9: openssl-1.0.1c-aliasing.patch

all patch applied, make && make test succeeded

#### bug fix

Patch23: openssl-1.0.2c-default-paths.patch
Patch24: openssl-1.0.2a-issuer-hash.patch

all patch applied, make && make test succeeded

#### functionality changes

Patch33: openssl-1.0.0-beta4-ca-dir.patch
Patch34: openssl-1.0.2a-x509.patch
Patch35: openssl-1.0.2a-version-add-engines.patch
Patch39: openssl-1.0.2a-ipv6-apps.patch

all patch applied, make && make test succeeded

Patch40: openssl-1.0.2i-fips.patch
Patch43: openssl-1.0.2j-krb5keytab.patch
Patch45: openssl-1.0.2a-env-zlib.patch
Patch47: openssl-1.0.2a-readme-warning.patch
Patch49: openssl-1.0.1i-algo-doc.patch
Patch50: openssl-1.0.2a-dtls1-abi.patch
Patch51: openssl-1.0.2a-version.patch
Patch56: openssl-1.0.2a-rsa-x931.patch
Patch58: openssl-1.0.2a-fips-md5-allow.patch
Patch60: openssl-1.0.2a-apps-dgst.patch
Patch63: openssl-1.0.2k-starttls.patch
Patch65: openssl-1.0.2i-chil-fixes.patch
Patch66: openssl-1.0.2h-pkgconfig.patch
Patch68: openssl-1.0.2i-secure-getenv.patch
Patch70: openssl-1.0.2a-fips-ec.patch
Patch71: openssl-1.0.2g-manfix.patch
Patch72: openssl-1.0.2a-fips-ctor.patch
Patch73: openssl-1.0.2c-ecc-suiteb.patch
Patch74: openssl-1.0.2j-deprecate-algos.patch
Patch75: openssl-1.0.2a-compat-symbols.patch
Patch76: openssl-1.0.2j-new-fips-reqs.patch
Patch77: openssl-1.0.2j-downgrade-strength.patch
Patch78: openssl-1.0.2k-cc-reqs.patch
Patch90: openssl-1.0.2i-enc-fail.patch
Patch94: openssl-1.0.2d-secp256k1.patch
Patch95: openssl-1.0.2e-remove-nistp224.patch
Patch96: openssl-1.0.2e-speed-doc.patch
Patch97: openssl-1.0.2k-no-ssl2.patch
Patch98: openssl-1.0.2k-long-hello.patch

#### backported fixes

Patch80: openssl-1.0.2e-wrap-pad.patch
Patch81: openssl-1.0.2a-padlock64.patch
Patch82: openssl-1.0.2i-trusted-first-doc.patch
Patch83: openssl-1.0.2k-backports.patch
Patch84: openssl-1.0.2k-ppc-update.patch
Patch85: openssl-1.0.2k-req-x509.patch


### 修改SHLIB文件版本

perl util/perlpath.pl `dirname %{__perl}`
然后将编译选项打印出来


### 编译

./Configure \
	--prefix=%{_prefix} --openssldir=%{_sysconfdir}/pki/tls ${sslflags} \
	zlib sctp enable-camellia enable-seed enable-tlsext enable-rfc3779 \
	enable-cms enable-md2 enable-rc5 \
	no-mdc2 no-ec2m no-gost no-srp \
	--with-krb5-flavor=MIT --enginesdir=%{_libdir}/openssl/engines \
	--with-krb5-dir=/usr shared  ${sslarch} %{?!nofips:fips}
RPM_OPT_FLAGS="$RPM_OPT_FLAGS -Wa,--noexecstack -DPURIFY"
make depend
make all
make rehash

拷贝其他的相关文件

清理pc文件

### 检查

revert patch33然后再进行测试
设置OPENSSL_ENABLE_MD5_VERIFY

make -C test tests apps

%{__cc} -o openssl-thread-test \
	`krb5-config --cflags` \
	-I./include \
	$RPM_OPT_FLAGS \
	%{SOURCE8} \
	-L. \
	-lssl -lcrypto \
	`krb5-config --libs` \
	-lpthread -lz -ldl
./openssl-thread-test --threads %{thread_test_threads}


--------
nohobble，然后不应用测试案例也能通过测试，后面可以考虑这种方法

hobble之后，由于删除掉了一些函数，这些函数无法必须再重新拿回来

先尝试hobble，然后再往回拿的策略：

shlib_target=; if [ -n "libcrypto.so.10 libssl.so.10" ]; then \
    shlib_target="linux-shared"; \
elif [ -n "" ]; then \
  FIPSLD_CC="gcc"; CC=/usr/local/ssl/fips-2.0/bin/fipsld; export CC FIPSLD_CC; \
fi; \
  LIBRARIES="-L.. -lssl -L/usr/lib -lgssapi_krb5 -lkrb5 -lcom_err -lk5crypto -L.. -lcrypto" ; \
make -f ../Makefile.shared -e \
APPNAME=openssl OBJECTS="openssl.o verify.o asn1pars.o req.o dgst.o dh.o dhparam.o enc.o passwd.o gendh.o errstr.o ca.o pkcs7.o crl2p7.o crl.o rsa.o rsautl.o dsa.o dsaparam.o ec.o ecparam.o x509.o genrsa.o gendsa.o genpkey.o s_server.o s_client.o speed.o s_time.o apps.o s_cb.o s_socket.o app_rand.o version.o sess_id.o ciphers.o nseq.o pkcs12.o pkcs8.o pkey.o pkeyparam.o pkeyutl.o spkac.o smime.o cms.o rand.o engine.o ocsp.o prime.o ts.o srp.o" \
LIBDEPS=" $LIBRARIES -Wl,-z,relro -ldl -lz" \
link_app.${shlib_target}
make[2]: Entering directory `/home/srzhao/upel-source/openssl/apps'
../libcrypto.so: undefined reference to `EC_GROUP_get_curve_GF2m'
../libcrypto.so: undefined reference to `EC_POINT_get_affine_coordinates_GF2m'
../libcrypto.so: undefined reference to `EC_POINT_set_affine_coordinates_GF2m'
collect2: error: ld returned 1 exit status


可以看到EC_GROUP_get_curve_GF2m在./crypto/sm2/sm2_lib.c中使用

声明在ec.h, 实现在ec_lib.c（声明被删除，但是实现还在）

解决方法：
重新在ec.h中添加回来。 依然还是有这个问题，经过分析是因为在Configure中使用了no-ec2m选项，导致ec2m相关的代码被删除，因此不使用ec2m选项将该算法相关的代码引入。



+++
类似地：
../libcrypto.so: undefined reference to `EC_GF2m_simple_method'
../libcrypto.so: undefined reference to `ec_GF2m_simple_point2oct'
../libcrypto.so: undefined reference to `ec_GF2m_simple_set_compressed_coordinates'
../libcrypto.so: undefined reference to `ec_GF2m_simple_oct2point'


这次是没有定义，但是有声明，并且在./crypto/ec/ec_cvt.c中使用了。
./crypto/ec/ec_oct.c中使用 ./crypto/ec/ec2_smpl.c中定义
./crypto/ec/ec2_oct.c中定义
./crypto/ec/ec2_oct.c中定义

再确认下是不是因为去掉no EC2造成的! 经过确认，以上代码是因为删除了no-ec2m选项导致引入了其他代码引起的。

+++++

确认下能不能不删除no-ec2m，只引入sm2需要的ec2m相关代码: 试试吧, 但是感觉sm算法应用大量ec2m中的代码, 可能不行！

确认了下，好像差不多解决了！

sm2_test.c: In function 'new_ec_group':
sm2_test.c:201:3: warning: implicit declaration of function 'EC_GROUP_new_curve_GF2m' [-Wimplicit-function-declaration]
if (!(group = EC_GROUP_new_curve_GF2m(p, a, b, ctx))) {
    ^
sm2_test.c:201:15: warning: assignment makes pointer from integer without a cast [enabled by default]
if (!(group = EC_GROUP_new_curve_GF2m(p, a, b, ctx))) {
^
make[2]: Entering directory `/home/srzhao/upel-source/openssl/test'
sm2_test.o: In function `new_ec_group':
sm2_test.c:(.text+0x507): undefined reference to `EC_GROUP_new_curve_GF2m'


so，再加一个EC_GROUP_new_curve_GF2m函数就好了？
在ec.h中声明，在./crypto/ec/ec_cvt.c中定义

再一次类似的问题：
EC_GF2m_simple_method: ec.h 声明， ./crypto/ec/ec2_smpl.c定义

again:

../libcrypto.so: undefined reference to `BN_GF2m_add'
../libcrypto.so: undefined reference to `BN_GF2m_mod_mul_arr'
../libcrypto.so: undefined reference to `BN_GF2m_mod_arr'
../libcrypto.so: undefined reference to `fips_ec_gf2m_simple_method'
../libcrypto.so: undefined reference to `BN_GF2m_mod_sqr_arr'
../libcrypto.so: undefined reference to `BN_GF2m_cmp'
../libcrypto.so: undefined reference to `ec_GF2m_simple_mul'
../libcrypto.so: undefined reference to `BN_GF2m_poly2arr'
../libcrypto.so: undefined reference to `ec_GF2m_have_precompute_mult'
../libcrypto.so: undefined reference to `ec_GF2m_precompute_mult'
../libcrypto.so: undefined reference to `BN_GF2m_mod_div'

这次他妈的是bn, ec2m都集中触发了

由于hobble过程中直接删除了bn/*_gf2m文件，导致以上函数都没有实现，因此加回来

还是有：
../libcrypto.so: undefined reference to `fips_ec_gf2m_simple_method'
../libcrypto.so: undefined reference to `BN_GF2m_cmp'
../libcrypto.so: undefined reference to `ec_GF2m_simple_mul'
../libcrypto.so: undefined reference to `ec_GF2m_have_precompute_mult'
../libcrypto.so: undefined reference to `ec_GF2m_precompute_mult'

again++:
../libcrypto.so: undefined reference to `fips_ec_gf2m_simple_method'
../libcrypto.so: undefined reference to `ec_GF2m_simple_mul'
../libcrypto.so: undefined reference to `ec_GF2m_have_precompute_mult'
../libcrypto.so: undefined reference to `ec_GF2m_precompute_mult'


```
127 # ifdef OPENSSL_FIPS
128     if (FIPS_mode())
129         return fips_ec_gf2m_simple_method();
130 # endif
```

rhel: 删除了fips_ec_gf2m_simple_method（未实现）调用代码EC_GF2m_simple_method，裁剪了ec2m模块
sm: 使用EC_GF2m_simple_method，使用rhel flags（enable fips)，因此调用了未实现的fips_ec_gf2m_simple_method函数
处理方法：删除127-130代码


添加以下文件
./crypto/ec/ec2_mult.c




^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^

oh yeah!!!!!

终于TMD编译过了！
^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^_^




