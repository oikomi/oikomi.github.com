---
layout: post
title: Squid源码分析(四)之请求命中代码
---

Squid源码分析(四)之请求命中代码
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2012/08/29/nginx_cache_4.html


clientProcessRequest 用来处理一个用户请求，

{% highlight c %}
static void
clientProcessRequest(clientHttpRequest * http)
{
	printf("%%%%%%%%%%####clientProcessRequest\n");
    char *url = http->uri;
    request_t *r = http->request;
    HttpReply *rep;
    debug(33, 4) ("clientProcessRequest: %s '%s'\n",
	RequestMethods[r->method].str,
	url);
    r->flags.collapsed = 0;
    if (httpHeaderHas(&r->header, HDR_EXPECT)) {
	int ignore = 0;
	if (Config.onoff.ignore_expect_100) {
	    String expect = httpHeaderGetList(&r->header, HDR_EXPECT);
	    if (strCaseCmp(expect, "100-continue") == 0)
		ignore = 1;
	    stringClean(&expect);
	}
	if (!ignore) {
	    ErrorState *err = errorCon(ERR_INVALID_REQ, HTTP_EXPECTATION_FAILED, r);
	    http->log_type = LOG_TCP_MISS;
	    http->entry = clientCreateStoreEntry(http, http->request->method, null_request_flags);
	    errorAppendEntry(http->entry, err);
	    return;
	}
    }
    if (r->method == METHOD_CONNECT && !http->redirect.status) {
	http->log_type = LOG_TCP_MISS;
#if USE_SSL && SSL_CONNECT_INTERCEPT
	if (Config.Sockaddr.https) {
	    static const char ok[] = "HTTP/1.0 200 Established\r\n\r\n";
	    write(http->conn->fd, ok, strlen(ok));
	    httpsAcceptSSL(http->conn, Config.Sockaddr.https->sslContext);
	    httpRequestFree(http);
	} else
#endif
	    sslStart(http, &http->out.size, &http->al.http.code);
	return;
    } else if (r->method == METHOD_PURGE) {
	clientPurgeRequest(http);
	return;
    } else if (r->method == METHOD_TRACE) {
	if (r->max_forwards == 0) {
	    http->log_type = LOG_TCP_HIT;
	    http->entry = clientCreateStoreEntry(http, r->method, null_request_flags);
	    storeReleaseRequest(http->entry);
	    storeBuffer(http->entry);
	    rep = httpReplyCreate();
	    httpReplySetHeaders(rep, HTTP_OK, NULL, "text/plain", httpRequestPrefixLen(r), -1, squid_curtime);
	    httpReplySwapOut(rep, http->entry);
	    httpRequestSwapOut(r, http->entry);
	    storeComplete(http->entry);
	    return;
	}
	/* yes, continue */
	http->log_type = LOG_TCP_MISS;
    } else {
	http->log_type = clientProcessRequest2(http);
    }
    debug(33, 4) ("clientProcessRequest: %s for '%s'\n",
	log_tags[http->log_type],
	http->uri);
    http->out.offset = 0;
    if (NULL != http->entry) {
	printf("##############NULL != http->entry \n");
	storeLockObject(http->entry);
	if (http->entry->store_status == STORE_PENDING && http->entry->mem_obj) {
	    if (http->entry->mem_obj->request)
		r->hier = http->entry->mem_obj->request->hier;
	}
	storeCreateMemObject(http->entry, http->uri);
	http->entry->mem_obj->method = r->method;
	http->sc = storeClientRegister(http->entry, http);
#if DELAY_POOLS
	delaySetStoreClient(http->sc, delayClient(http));
#endif
	storeClientCopyHeaders(http->sc, http->entry,
	    clientCacheHit,
	    http);
    } else {
	/* MISS CASE, http->log_type is already set! */
	clientProcessMiss(http);
    }
}
{% endhighlight %}

通过调用clientProcessRequest2

{% highlight c %}
static log_type
clientProcessRequest2(clientHttpRequest * http)
{
	printf("###########clientProcessRequest2 \n");
    request_t *r = http->request;
    StoreEntry *e;
    if (r->flags.cachable || r->flags.internal)
	e = http->entry = storeGetPublicByRequest(r);
    else
	e = http->entry = NULL;
    /* Release IP-cache entries on reload */
    if (r->flags.nocache) {
#if USE_DNSSERVERS
	ipcacheInvalidate(r->host);
#else
	ipcacheInvalidateNegative(r->host);
#endif /* USE_DNSSERVERS */
    }
#if HTTP_VIOLATIONS
    else if (r->flags.nocache_hack) {
#if USE_DNSSERVERS
	ipcacheInvalidate(r->host);
#else
	ipcacheInvalidateNegative(r->host);
#endif /* USE_DNSSERVERS */
    }
#endif /* HTTP_VIOLATIONS */
#if USE_CACHE_DIGESTS
    http->lookup_type = e ? "HIT" : "MISS";
#endif
    if (NULL == e) {
	/* this object isn't in the cache */
	debug(33, 3) ("clientProcessRequest2: storeGet() MISS\n");
	if (r->vary) {
	    if (r->done_etag) {
		debug(33, 2) ("clientProcessRequest2: ETag loop\n");
	    } else if (r->etags) {
		debug(33, 2) ("clientProcessRequest2: ETag miss\n");
		r->etags = NULL;
	    } else if (r->vary->etags.count > 0) {
		r->etags = &r->vary->etags;
	    }
	}
	return LOG_TCP_MISS;
    }
    if (Config.onoff.offline) {
	debug(33, 3) ("clientProcessRequest2: offline HIT\n");
	http->entry = e;
	return LOG_TCP_HIT;
    }
    if (http->redirect.status) {
	/* force this to be a miss */
	http->entry = NULL;
	return LOG_TCP_MISS;
    }
    if (!storeEntryValidToSend(e)) {
	debug(33, 3) ("clientProcessRequest2: !storeEntryValidToSend MISS\n");
	http->entry = NULL;
	return LOG_TCP_MISS;
    }
    if (EBIT_TEST(e->flags, KEY_EARLY_PUBLIC)) {
	if (clientOnlyIfCached(http)) {
	    debug(33, 3) ("clientProcessRequest2: collapsed only-if-cached MISS\n");
	    http->entry = NULL;
	    return LOG_TCP_MISS;
	}
	r->flags.collapsed = 1;	/* Don't trust the store entry */
    }
    if (EBIT_TEST(e->flags, ENTRY_SPECIAL)) {
	/* Special entries are always hits, no matter what the client says */
	debug(33, 3) ("clientProcessRequest2: ENTRY_SPECIAL HIT\n");
	http->entry = e;
	return LOG_TCP_HIT;
    }
    if (r->flags.nocache) {
	debug(33, 3) ("clientProcessRequest2: no-cache REFRESH MISS\n");
	http->entry = NULL;
	return LOG_TCP_CLIENT_REFRESH_MISS;
    }
    if (NULL == r->range) {
	(void) 0;
    } else if (httpHdrRangeWillBeComplex(r->range)) {
	/*
	 * Some clients break if we return "200 OK" for a Range
	 * request.  We would have to return "200 OK" for a _complex_
	 * Range request that is also a HIT. Thus, let's prevent HITs
	 * on complex Range requests
	 */
	debug(33, 3) ("clientProcessRequest2: complex range MISS\n");
	http->entry = NULL;
	return LOG_TCP_MISS;
    } else if (clientCheckRangeForceMiss(e, r->range)) {
	debug(33, 3) ("clientProcessRequest2: forcing miss due to range_offset_limit\n");
	http->entry = NULL;
	return LOG_TCP_MISS;
    }
    debug(33, 3) ("clientProcessRequest2: default HIT\n");
    http->entry = e;
    return LOG_TCP_HIT;
}
{% endhighlight %}

{% highlight c %}
StoreEntry *
storeGetPublicByRequest(request_t * req)
{
    StoreEntry *e = storeGetPublicByRequestMethod(req, req->method);
    if (e == NULL && req->method == METHOD_HEAD)
	/* We can generate a HEAD reply from a cached GET object */
	e = storeGetPublicByRequestMethod(req, METHOD_GET);
    return e;
}
{% endhighlight %}

{% highlight c %}
StoreEntry *
storeGetPublicByRequestMethod(request_t * req, const method_t method)
{
    if (req->vary) {
	/* Varying objects... */
	if (req->vary->key)
	    return storeGet(storeKeyScan(req->vary->key));
	else
	    return NULL;
    }
    return storeGet(storeKeyPublicByRequestMethod(req, method));
}
{% endhighlight %}


{% highlight c %}
/* Lookup an object in the cache.
 * return just a reference to object, don't start swapping in yet. */
StoreEntry *
storeGet(const cache_key * key)
{
    debug(20, 3) ("storeGet: looking up %s\n", storeKeyText(key));
    return (StoreEntry *) hash_lookup(store_table, key);
}
{% endhighlight %}


