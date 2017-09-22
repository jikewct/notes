# yum

怎么通过yum向rpm传送命令--noplugins或者--nosignatures

其实setVSFlags应该就可以了

使用--nogpgcheck, 命令行

研究--nogpgcheck 命令行是怎么传送的！！！

--nogpgcheck传送到yum中
opts.nogpgcheck == True
base._override_sigchecks==True && repo._override_sigchecks == True

docheck->checkGpgKey->base.gpgKey(sig)Check()->sigCheckPkg 执行检查

