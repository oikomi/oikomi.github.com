---
layout: post
title: Squid源码分析(一)之基础存储路径
---


> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2012/08/22/nginx_cache_1.html

main ---- > storeFsInit

关于storeFsInit 这个函数，其实是做了2步：

其一：建立替换算法

其二：建立fs

{% highlight java %}
void
storeFsInit(void)
{
    storeReplSetup();
    storeFsSetup();
}
{% endhighlight %}

首先跟踪storeFsSetup 
注意该函数是由./store_modules.sh ufs aufs coss null diskd 自动生成，需要编译后才有该函数。

{% highlight java %}
void storeFsSetup(void)
{
	storeFsAdd("ufs", storeFsSetup_ufs);
	storeFsAdd("aufs", storeFsSetup_aufs);
	storeFsAdd("coss", storeFsSetup_coss);
	storeFsAdd("null", storeFsSetup_null);
	storeFsAdd("diskd", storeFsSetup_diskd);
}
{% endhighlight %}

对于storeFsAdd，这里有一个非常重要的storefs_list全局变量，它保存了全部的fs信息。看该函数下面最后一句的回调

{% highlight java %}
void
storeFsAdd(const char *type, STSETUP * setup)
{
    int i;
    /* find the number of currently known storefs types */
    for (i = 0; storefs_list && storefs_list[i].typestr; i++) {
	assert(strcmp(storefs_list[i].typestr, type) != 0);
    }
    /* add the new type */
    storefs_list = xrealloc(storefs_list, (i + 2) * sizeof(storefs_entry_t));
    memset(&storefs_list[i + 1], 0, sizeof(storefs_entry_t));
    storefs_list[i].typestr = type;
    /* Call the FS to set up capabilities and initialize the FS driver */
    setup(&storefs_list[i]);
}
{% endhighlight %}

我们跟踪ufs系统看看，

{% highlight java %}
void
storeFsSetup_ufs(storefs_entry_t * storefs)
{
    assert(!ufs_initialised);
    storefs->parsefunc = storeUfsDirParse;
    storefs->reconfigurefunc = storeUfsDirReconfigure;
    storefs->donefunc = storeUfsDirDone;
    ufs_state_pool = memPoolCreate("UFS IO State data", sizeof(ufsstate_t));
    ufs_initialised = 1;
}
{% endhighlight %}

可以看出该函数是用来填充storefs_list全局变量相对ufs部分的，并置ufs_initialised = 1; 其中 storefs->parsefunc = storeUfsDirParse;比较重要。

我们继续跟踪storeAufsDirParse (注意storeAufsDirParse 是在parse_cachedir函数中调用)

{% highlight java %}
/*
 * storeUfsDirParse
 *
 * Called when a *new* fs is being setup.
 */
static void
storeUfsDirParse(SwapDir * sd, int index, char *path)
{
    int i;
    int size;
    int l1;
    int l2;
    ufsinfo_t *ufsinfo;

    i = GetInteger();
    size = i << 10;		/* Mbytes to kbytes */
    if (size <= 0)
	fatal("storeUfsDirParse: invalid size value");
    i = GetInteger();
    l1 = i;
    if (l1 <= 0)
	fatal("storeUfsDirParse: invalid level 1 directories value");
    i = GetInteger();
    l2 = i;
    if (l2 <= 0)
	fatal("storeUfsDirParse: invalid level 2 directories value");

    ufsinfo = xmalloc(sizeof(ufsinfo_t));
    if (ufsinfo == NULL)
	fatal("storeUfsDirParse: couldn't xmalloc() ufsinfo_t!\n");

    sd->index = index;
    sd->path = xstrdup(path);
    sd->max_size = size;
    sd->fsdata = ufsinfo;
    ufsinfo->l1 = l1;
    ufsinfo->l2 = l2;
    ufsinfo->swaplog_fd = -1;
    ufsinfo->map = NULL;	/* Debugging purposes */
    ufsinfo->suggest = 0;
    ufsinfo->open_files = 0;
    sd->checkconfig = storeUfsCheckConfig;
    sd->init = storeUfsDirInit;
    sd->newfs = storeUfsDirNewfs;
    sd->dump = storeUfsDirDump;
    sd->freefs = storeUfsDirFree;
    sd->dblcheck = storeUfsCleanupDoubleCheck;
    sd->statfs = storeUfsDirStats;
    sd->maintainfs = storeUfsDirMaintain;
    sd->checkobj = storeUfsDirCheckObj;
    sd->checkload = storeUfsDirCheckLoadAv;
    sd->refobj = storeUfsDirRefObj;
    sd->unrefobj = storeUfsDirUnrefObj;
    sd->callback = NULL;
    sd->sync = NULL;
    sd->obj.create = storeUfsCreate;
    sd->obj.open = storeUfsOpen;
    sd->obj.close = storeUfsClose;
    sd->obj.read = storeUfsRead;
    sd->obj.write = storeUfsWrite;
    sd->obj.unlink = storeUfsUnlink;
    sd->obj.recycle = storeUfsRecycle;
    sd->log.open = storeUfsDirOpenSwapLog;
    sd->log.close = storeUfsDirCloseSwapLog;
    sd->log.write = storeUfsDirSwapLog;
    sd->log.clean.start = storeUfsDirWriteCleanStart;
    sd->log.clean.nextentry = storeUfsDirCleanLogNextEntry;
    sd->log.clean.done = storeUfsDirWriteCleanDone;

    parse_cachedir_options(sd, options, 1);

    /* Initialise replacement policy stuff */
    sd->repl = createRemovalPolicy(Config.replPolicy);
}
{% endhighlight %}

该函数较长，其主要就是填充_SwapDir结构体(非常重要，另外分析)

{% highlight c %}
    sd->obj.create = storeUfsCreate;
    sd->obj.open = storeUfsOpen;
    sd->obj.close = storeUfsClose;
    sd->obj.read = storeUfsRead;
    sd->obj.write = storeUfsWrite;
    sd->obj.unlink = storeUfsUnlink;
    sd->obj.recycle = storeUfsRecycle;
{% endhighlight %}

重点看上面几句，其表示了关于存储IO的回调函数设置。

我们看看storeUfsRead

{% highlight c %}
void
storeUfsRead(SwapDir * SD, storeIOState * sio, char *buf, size_t size, squid_off_t offset, STRCB * callback, void *callback_data)
{
    ufsstate_t *ufsstate = (ufsstate_t *) sio->fsstate;

    assert(sio->read.callback == NULL);
    assert(sio->read.callback_data == NULL);
    sio->read.callback = callback;
    sio->read.callback_data = callback_data;
    cbdataLock(callback_data);
    debug(79, 3) ("storeUfsRead: dirno %d, fileno %08X, FD %d\n",
	sio->swap_dirn, sio->swap_filen, ufsstate->fd);
    sio->offset = offset;
    ufsstate->flags.reading = 1;
    file_read(ufsstate->fd,
	buf,
	size,
	(off_t) offset,
	storeUfsReadDone,
	sio);
}
{% endhighlight %}

ufs是调用file_read

file_read - diskHandleRead - FD_READ_METHOD
 
{% highlight c %}
#define FD_READ_METHOD(fd, buf, len) (*fd_table[fd].read_method)(fd, buf, len)
{% endhighlight %}

注意fd_table是一个全局变量，它以文件fd为索引。

其中read_method 是在下面 fd_open 中赋值的

{% highlight c %}
void
fd_open(int fd, unsigned int type, const char *desc)
{
    fde *F;
    assert(fd >= 0);
    F = &fd_table[fd];
    if (F->flags.open) {
	debug(51, 1) ("WARNING: Closing open FD %4d\n", fd);
	fd_close(fd);
    }
    assert(!F->flags.open);
    debug(51, 3) ("fd_open FD %d %s\n", fd, desc);
    F->type = type;
    F->flags.open = 1;
    commOpen(fd);
#ifdef _SQUID_MSWIN_
    F->win32.handle = _get_osfhandle(fd);
    switch (type) {
    case FD_SOCKET:
    case FD_PIPE:
	F->read_method = &socket_read_method;
	F->write_method = &socket_write_method;
	break;
    case FD_FILE:
    case FD_LOG:
	F->read_method = &file_read_method;
	F->write_method = &file_write_method;
	break;
    default:
	fatalf("fd_open(): unknown FD type - FD#: %i, type: %u, desc %s\n", fd, type, desc);
    }
#else
    F->read_method = &default_read_method;
    F->write_method = &default_write_method;
#endif
    fdUpdateBiggest(fd, 1);
    if (desc)
	fd_note(fd, desc);
    Number_FD++;
}
{% endhighlight %}

所以就进入了file_read_method， 在调用系统 _read

{% highlight c %}
int
file_read_method(int fd, char *buf, int len)
{
    return (_read(fd, buf, len));
}
{% endhighlight %}

