---
layout: post
title: Squid源码分析(五)之业务逻辑分析
---


Squid源码分析(五)之业务逻辑分析
=====================

> **NOTE:** The de(#).

收到请求后，根据请求的URL和method 进行hash生成键值, 在全局哈希表store_table 中进行查找， 若命中则调用storeClientCopy 拷贝数据； 若没有命中则转发后端服务器，在调用storeAppend把数据交给squid存储系统并转发给用户。

	对于命中：

storeClientCopy --- > storeClientCopy2 - storeClientCopy3   stmemCopy / storeClientFileRead  - storeRead

那好，我们看storeRead

{% highlight java %}
void
storeRead(storeIOState * sio, char *buf, size_t size, squid_off_t offset, STRCB * callback, void *callback_data)
{
    SwapDir *SD = &Config.cacheSwap.swapDirs[sio->swap_dirn];
    (SD->obj.read) (SD, sio, buf, size, offset, callback, callback_data);
}
{% endhighlight %}

上面红色字段的read回调在哪里赋值的呢。Ok, 我们前面已经分析了

{% highlight java %}
    sd->obj.create = storeUfsCreate;
    sd->obj.open = storeUfsOpen;
    sd->obj.close = storeUfsClose;
    sd->obj.read = storeUfsRead;
    sd->obj.write = storeUfsWrite;
    sd->obj.unlink = storeUfsUnlink;
sd->obj.recycle = storeUfsRecycle;
{% endhighlight %}

至此，会根据不同的文件系统类型进行相关调用，后续分析见上面了。

	对于未命中：

对于storeAppend而言，该函数非常重要的完成了几个业务

{% highlight java %}
/* Append incoming data from a primary server to an entry. */
void
storeAppend(StoreEntry * e, const char *buf, int len)
{
    MemObject *mem = e->mem_obj;
    assert(mem != NULL);
    assert(len >= 0);
    assert(e->store_status == STORE_PENDING);
    mem->refresh_timestamp = squid_curtime;
    if (len) {
	debug(20, 5) ("storeAppend: appending %d bytes for '%s'\n",
	    len,
	    storeKeyText(e->hash.key));
	storeGetMemSpace(len);
	stmemAppend(&mem->data_hdr, buf, len);
	mem->inmem_hi += len;
    }
    if (EBIT_TEST(e->flags, DELAY_SENDING))
	return;
    InvokeHandlers(e);
    storeSwapOut(e);
}
{% endhighlight %}

storeGetMemSpace  ----  内存判断，以便是否启动替换机制

stmemAppend  -----  将数据拷贝到_MemObject的data_hdr中

InvokeHandlers  ---- 通过_MemObject的client找到客户端，并将数据发送给所有客户端

storeSwapOut  -----  数据存盘

上面四个业务非常重要
我们跟踪看一下storeSwapOut  

{% highlight java %}
void
storeSwapOut(StoreEntry * e)
{
    MemObject *mem = e->mem_obj;
    int swapout_able;
    squid_off_t swapout_size;
    size_t swap_buf_len;
    if (mem == NULL)
	return;
    /* should we swap something out to disk? */
    debug(20, 7) ("storeSwapOut: %s\n", storeUrl(e));
    debug(20, 7) ("storeSwapOut: store_status = %s\n",
	storeStatusStr[e->store_status]);
    if (EBIT_TEST(e->flags, ENTRY_ABORTED)) {
	assert(EBIT_TEST(e->flags, RELEASE_REQUEST));
	storeSwapOutFileClose(e);
	return;
    }
    if (EBIT_TEST(e->flags, ENTRY_SPECIAL)) {
	debug(20, 3) ("storeSwapOut: %s SPECIAL\n", storeUrl(e));
	return;
    }
    debug(20, 7) ("storeSwapOut: mem->inmem_lo = %" PRINTF_OFF_T "\n",
	mem->inmem_lo);
    debug(20, 7) ("storeSwapOut: mem->inmem_hi = %" PRINTF_OFF_T "\n",
	mem->inmem_hi);
    debug(20, 7) ("storeSwapOut: swapout.queue_offset = %" PRINTF_OFF_T "\n",
	mem->swapout.queue_offset);
    if (mem->swapout.sio)
	debug(20, 7) ("storeSwapOut: storeOffset() = %" PRINTF_OFF_T "\n",
	    storeOffset(mem->swapout.sio));
    assert(mem->inmem_hi >= mem->swapout.queue_offset);
    /*
     * Grab the swapout_size and check to see whether we're going to defer
     * the swapout based upon size
     */
    swapout_size = mem->inmem_hi - mem->swapout.queue_offset;
    if ((e->store_status != STORE_OK) && (swapout_size < store_maxobjsize)) {
	/*
	 * NOTE: the store_maxobjsize here is the max of optional
	 * max-size values from 'cache_dir' lines.  It is not the
	 * same as 'maximum_object_size'.  By default, store_maxobjsize
	 * will be set to -1.  However, I am worried that this
	 * deferance may consume a lot of memory in some cases.
	 * It would be good to make this decision based on reply
	 * content-length, rather than wait to accumulate huge
	 * amounts of object data in memory.
	 */
	debug(20, 5) ("storeSwapOut: Deferring starting swapping out\n");
	return;
    }
    swapout_able = storeSwapOutMaintainMemObject(e);
#if SIZEOF_SQUID_OFF_T <= 4
    if (mem->inmem_hi > 0x7FFF0000) {
	debug(20, 0) ("WARNING: preventing squid_off_t overflow for %s\n", storeUrl(e));
	storeAbort(e);
	return;
    }
#endif
    if (!swapout_able)
	return;
    debug(20, 7) ("storeSwapOut: swapout_size = %" PRINTF_OFF_T "\n",
	swapout_size);
    if (swapout_size == 0) {
	if (e->store_status == STORE_OK)
	    storeSwapOutFileClose(e);
	return;			/* Nevermore! */
    }
    if (e->store_status == STORE_PENDING) {
	/* wait for a full block to write */
	if (swapout_size < SM_PAGE_SIZE)
	    return;
	/*
	 * Wait until we are below the disk FD limit, only if the
	 * next server-side read won't be deferred.
	 */
	if (storeTooManyDiskFilesOpen() && !fwdCheckDeferRead(-1, e))
	    return;
    }
    /* Ok, we have stuff to swap out.  Is there a swapout.sio open? */
    if (e->swap_status == SWAPOUT_NONE && !EBIT_TEST(e->flags, ENTRY_FWD_HDR_WAIT)) {
	assert(mem->swapout.sio == NULL);
	assert(mem->inmem_lo == 0);
	if (storeCheckCachable(e))
	    storeSwapOutStart(e);
	else {
	    /* Now that we know the data is not cachable, free the memory
	     * to make sure the forwarding code does not defer the connection
	     */
	    storeSwapOutMaintainMemObject(e);
	    return;
	}
	/* ENTRY_CACHABLE will be cleared and we'll never get here again */
    }
    if (NULL == mem->swapout.sio)
	return;
    do {
	/*
	 * Evil hack time.
	 * We are paging out to disk in page size chunks. however, later on when
	 * we update the queue position, we might not have a page (I *think*),
	 * so we do the actual page update here.
	 */

	if (mem->swapout.memnode == NULL) {
	    /* We need to swap out the first page */
	    mem->swapout.memnode = mem->data_hdr.head;
	} else {
	    /* We need to swap out the next page */
	    mem->swapout.memnode = mem->swapout.memnode->next;
	}
	/*
	 * Get the length of this buffer. We are assuming(!) that the buffer
	 * length won't change on this buffer, or things are going to be very
	 * strange. I think that after the copy to a buffer is done, the buffer
	 * size should stay fixed regardless so that this code isn't confused,
	 * but we can look at this at a later date or whenever the code results
	 * in bad swapouts, whichever happens first. :-)
	 */
	swap_buf_len = mem->swapout.memnode->len;

	debug(20, 3) ("storeSwapOut: swap_buf_len = %d\n", (int) swap_buf_len);
	assert(swap_buf_len > 0);
	debug(20, 3) ("storeSwapOut: swapping out %d bytes from %" PRINTF_OFF_T "\n",
	    (int) swap_buf_len, mem->swapout.queue_offset);
	mem->swapout.queue_offset += swap_buf_len;
	storeWrite(mem->swapout.sio, stmemNodeGet(mem->swapout.memnode), swap_buf_len, stmemNodeFree);
	/* the storeWrite() call might generate an error */
	if (e->swap_status != SWAPOUT_WRITING)
	    break;
	swapout_size = mem->inmem_hi - mem->swapout.queue_offset;
	if (e->store_status == STORE_PENDING)
	    if (swapout_size < SM_PAGE_SIZE)
		break;
    } while (swapout_size > 0);
    if (NULL == mem->swapout.sio)
	/* oops, we're not swapping out any more */
	return;
    if (e->store_status == STORE_OK) {
	/*
	 * If the state is STORE_OK, then all data must have been given
	 * to the filesystem at this point because storeSwapOut() is
	 * not going to be called again for this entry.
	 */
	assert(mem->inmem_hi == mem->swapout.queue_offset);
	storeSwapOutFileClose(e);
    }
}
{% endhighlight %}

{% highlight java %}
squid有个MaintainMemObject周期执行事件，显然此处不是，所以

/* start swapping object to disk */
static void
storeSwapOutStart(StoreEntry * e)
{
    generic_cbdata *c;
    MemObject *mem = e->mem_obj;
    int swap_hdr_sz = 0;
    tlv *tlv_list;
    char *buf;
    assert(mem);
    /* Build the swap metadata, so the filesystem will know how much
     * metadata there is to store
     */
    debug(20, 5) ("storeSwapOutStart: Begin SwapOut '%s' to dirno %d, fileno %08X\n",
	storeUrl(e), e->swap_dirn, e->swap_filen);
    e->swap_status = SWAPOUT_WRITING;
    tlv_list = storeSwapMetaBuild(e);
    buf = storeSwapMetaPack(tlv_list, &swap_hdr_sz);
    storeSwapTLVFree(tlv_list);
    mem->swap_hdr_sz = (size_t) swap_hdr_sz;
    /* Create the swap file */
    c = cbdataAlloc(generic_cbdata);
    c->data = e;
    mem->swapout.sio = storeCreate(e, storeSwapOutFileNotify, storeSwapOutFileClosed, c);
    if (NULL == mem->swapout.sio) {
	e->swap_status = SWAPOUT_NONE;
	cbdataFree(c);
	xfree(buf);
	storeLog(STORE_LOG_SWAPOUTFAIL, e);
	return;
    }
    storeLockObject(e);		/* Don't lock until after create, or the replacement
				 * code might get confused */
    /* Pick up the file number if it was assigned immediately */
    e->swap_filen = mem->swapout.sio->swap_filen;
    e->swap_dirn = mem->swapout.sio->swap_dirn;
    /* write out the swap metadata */
    cbdataLock(mem->swapout.sio);
    storeWrite(mem->swapout.sio, buf, mem->swap_hdr_sz, xfree);
}
{% endhighlight %}

继续跟踪

{% highlight java %}
void
storeWrite(storeIOState * sio, char *buf, size_t size, FREE * free_func)
{
    SwapDir *SD = &Config.cacheSwap.swapDirs[sio->swap_dirn];
    squid_off_t offset = sio->write_offset;
    sio->write_offset += size;
    (SD->obj.write) (SD, sio, buf, size, offset, free_func);
}
{% endhighlight %}

好的，又回到了上面的分析了，开始写盘。
