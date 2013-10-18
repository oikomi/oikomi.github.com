---
layout: post
title: Squid源码分析(三)之后端转发请求
---

Squid源码分析(三)之后端转发请求
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2012/08/27/squid_cache_3.html



{% highlight c %}
void
fwdStart(int fd, StoreEntry * e, request_t * r)
{
	printf("#########fwdStart\n");
    FwdState *fwdState;
    int answer;
    ErrorState *err;
    /*
     * client_addr == no_addr indicates this is an "internal" request
     * from peer_digest.c, asn.c, netdb.c, etc and should always
     * be allowed.  yuck, I know.
     */
    if (r->client_addr.s_addr != no_addr.s_addr && r->protocol != PROTO_INTERNAL && r->protocol != PROTO_CACHEOBJ) {
	/*      
	 * Check if this host is allowed to fetch MISSES from us (miss_access)
	 */
	answer = aclCheckFastRequest(Config.accessList.miss, r);
	if (answer == 0) {
	    err_type page_id;
	    page_id = aclGetDenyInfoPage(&Config.denyInfoList, AclMatchedName, 1);
	    if (page_id == ERR_NONE)
		page_id = ERR_FORWARDING_DENIED;
	    err = errorCon(page_id, HTTP_FORBIDDEN, r);
	    errorAppendEntry(e, err);
	    return;
	}
    }
    debug(17, 3) ("fwdStart: '%s'\n", storeUrl(e));
    if (!e->mem_obj->request)
	e->mem_obj->request = requestLink(r);
#if URL_CHECKSUM_DEBUG
    assert(e->mem_obj->chksum == url_checksum(e->mem_obj->url));
#endif
    if (shutting_down) {
	/* more yuck */
	err = errorCon(ERR_SHUTTING_DOWN, HTTP_GATEWAY_TIMEOUT, r);
	errorAppendEntry(e, err);
	return;
    }
    switch (r->protocol) {
	/*
	 * Note, don't create fwdState for these requests
	 */
    case PROTO_INTERNAL:
	//printf("##########PROTO_INTERNAL \n");
	internalStart(r, e);
	return;
    case PROTO_CACHEOBJ:
	cachemgrStart(fd, r, e);
	return;
    case PROTO_URN:
	urnStart(r, e);
	return;
    default:
	break;
    }
    fwdState = cbdataAlloc(FwdState);
    fwdState->entry = e;
    fwdState->client_fd = fd;
    fwdState->server_fd = -1;
    fwdState->request = requestLink(r);
    fwdState->start = squid_curtime;
    fwdState->orig_entry_flags = e->flags;

#if LINUX_TPROXY
    /* If we need to transparently proxy the request
     * then we need the client source address and port */
    fwdState->src.sin_family = AF_INET;
    fwdState->src.sin_addr = r->client_addr;
    fwdState->src.sin_port = r->client_port;
#endif

    storeLockObject(e);
    if (!fwdState->request->flags.pinned)
	EBIT_SET(e->flags, ENTRY_FWD_HDR_WAIT);
    storeRegisterAbort(e, fwdAbort, fwdState);
    peerSelect(r, e, fwdStartComplete, fwdState);
}
{% endhighlight %}


{% highlight c %}
void
peerSelect(request_t * request,
    StoreEntry * entry,
    PSC * callback,
    void *callback_data)
{
	printf("##########peerSelect \n");
    ps_state *psstate;
    if (entry)
	debug(44, 3) ("peerSelect: %s\n", storeUrl(entry));
    else
	debug(44, 3) ("peerSelect: %s\n", RequestMethods[request->method].str);
    psstate = cbdataAlloc(ps_state);
    psstate->request = requestLink(request);
    psstate->entry = entry;
    psstate->callback = callback;
    psstate->callback_data = callback_data;
    psstate->direct = DIRECT_UNKNOWN;
#if USE_CACHE_DIGESTS
    request->hier.peer_select_start = current_time;
#endif
    if (psstate->entry)
	storeLockObject(psstate->entry);
    cbdataLock(callback_data);
    peerSelectFoo(psstate);
}
{% endhighlight %}

{% highlight c %}
static void
peerSelectFoo(ps_state * ps)
{
	printf("#########peerSelectFoo \n");
    StoreEntry *entry = ps->entry;
    request_t *request = ps->request;
    debug(44, 3) ("peerSelectFoo: '%s %s'\n",
	RequestMethods[request->method].str,
	request->host);
    if (ps->direct == DIRECT_UNKNOWN) {
	if (ps->always_direct == 0 && Config.accessList.AlwaysDirect) {
	    ps->acl_checklist = aclChecklistCreate(
		Config.accessList.AlwaysDirect,
		request,
		NULL);		/* ident */
	    aclNBCheck(ps->acl_checklist,
		peerCheckAlwaysDirectDone,
		ps);
	    return;
	} else if (ps->always_direct > 0) {
	    ps->direct = DIRECT_YES;
	} else if (ps->never_direct == 0 && Config.accessList.NeverDirect) {
	    ps->acl_checklist = aclChecklistCreate(
		Config.accessList.NeverDirect,
		request,
		NULL);		/* ident */
	    aclNBCheck(ps->acl_checklist,
		peerCheckNeverDirectDone,
		ps);
	    return;
	} else if (ps->never_direct > 0) {
	    ps->direct = DIRECT_NO;
	} else if (request->flags.no_direct) {
	    ps->direct = DIRECT_NO;
	} else if (request->flags.loopdetect) {
	    ps->direct = DIRECT_YES;
	} else if (peerCheckNetdbDirect(ps)) {
	    ps->direct = DIRECT_YES;
	} else {
	    ps->direct = DIRECT_MAYBE;
	}
	debug(44, 3) ("peerSelectFoo: direct = %s\n",
	    DirectStr[ps->direct]);
    }
    if (!entry || entry->ping_status == PING_NONE)
	peerGetPinned(ps);
    if (entry == NULL) {
	(void) 0;
    } else if (entry->ping_status == PING_NONE) {
	peerGetSomeNeighbor(ps);
	if (entry->ping_status == PING_WAITING)
	    return;
    } else if (entry->ping_status == PING_WAITING) {
	peerGetSomeNeighborReplies(ps);
	entry->ping_status = PING_DONE;
    }
    switch (ps->direct) {
    case DIRECT_YES:
	peerGetSomeDirect(ps);
	break;
    case DIRECT_NO:
	peerGetSomeParent(ps);
	peerGetAllParents(ps);
	break;
    default:
	if (Config.onoff.prefer_direct)
	    peerGetSomeDirect(ps);
	if (request->flags.hierarchical || !Config.onoff.nonhierarchical_direct)
	    peerGetSomeParent(ps);
	if (!Config.onoff.prefer_direct)
	    peerGetSomeDirect(ps);
	break;
    }
    peerSelectCallback(ps);
}
{% endhighlight %}


{% highlight c %}
static void
peerSelectCallback(ps_state * psstate)
{
	printf("#########peerSelectCallback \n");
    StoreEntry *entry = psstate->entry;
    FwdServer *fs = psstate->servers;
    void *data = psstate->callback_data;
    if (entry) {
	debug(44, 3) ("peerSelectCallback: %s\n", storeUrl(entry));
	if (entry->ping_status == PING_WAITING)
	    eventDelete(peerPingTimeout, psstate);
	entry->ping_status = PING_DONE;
    }
    if (fs == NULL) {
	debug(44, 1) ("Failed to select source for '%s'\n", storeUrl(entry));
	debug(44, 1) ("  always_direct = %d\n", psstate->always_direct);
	debug(44, 1) ("   never_direct = %d\n", psstate->never_direct);
	debug(44, 1) ("       timedout = %d\n", psstate->ping.timedout);
    }
    psstate->ping.stop = current_time;
    psstate->request->hier.ping = psstate->ping;
    if (cbdataValid(data)) {
	psstate->servers = NULL;
	psstate->callback(fs, data);
    }
    cbdataUnlock(data);
    peerSelectStateFree(psstate);
}
{% endhighlight %}


{% highlight c %}
static void
fwdStartComplete(FwdServer * servers, void *data)
{
	printf("###########fwdStartComplete \n");
    FwdState *fwdState = data;
    debug(17, 3) ("fwdStartComplete: %s\n", storeUrl(fwdState->entry));
    if (servers != NULL) {
	fwdState->servers = servers;
	fwdConnectStart(fwdState);
    } else {
	fwdStartFail(fwdState);
    }
}
{% endhighlight %}



{% highlight c %}
static void
fwdConnectStart(void *data)
{
	printf("##########fwdConnectStart \n");
    FwdState *fwdState = data;
    const char *url = storeUrl(fwdState->entry);
    int fd = -1;
    ErrorState *err;
    FwdServer *fs = fwdState->servers;
    const char *host;
    const char *name;
    unsigned short port;
    const char *domain = NULL;
    int ctimeout;
    int ftimeout = Config.Timeout.forward - (squid_curtime - fwdState->start);
    struct in_addr outgoing;
    unsigned short tos;
#if LINUX_TPROXY
    struct in_tproxy itp;
#endif
    int idle = -1;

    assert(fs);
    assert(fwdState->server_fd == -1);
    debug(17, 3) ("fwdConnectStart: %s\n", url);
    if (fs->peer) {
	host = fs->peer->host;
	name = fs->peer->name;
	port = fs->peer->http_port;
	if (fs->peer->options.originserver)
	    domain = fwdState->request->host;
	else
	    domain = "*";
	ctimeout = fs->peer->connect_timeout > 0 ? fs->peer->connect_timeout
	    : Config.Timeout.peer_connect;
    } else {
	host = name = fwdState->request->host;
	port = fwdState->request->port;
	ctimeout = Config.Timeout.connect;
    }
    if (ftimeout < 0)
	ftimeout = 5;
    if (ftimeout < ctimeout)
	ctimeout = ftimeout;
    fwdState->request->flags.pinned = 0;
    if (fs->code == PINNED) {
	int auth;
	fd = clientGetPinnedConnection(fwdState->request->pinned_connection, fwdState->request, fs->peer, &auth);
	if (fd >= 0) {
#if 0
	    if (!fs->peer)
		fs->code = HIER_DIRECT;
#endif
	    fwdState->server_fd = fd;
	    fwdState->n_tries++;
	    fwdState->request->flags.pinned = 1;
	    if (auth)
		fwdState->request->flags.auth = 1;
	    comm_add_close_handler(fd, fwdServerClosed, fwdState);
	    fwdConnectDone(fd, COMM_OK, fwdState);
	    return;
	}
	/* Failure. Fall back on next path */
	cbdataUnlock(fwdState->request->pinned_connection);
	fwdState->request->pinned_connection = NULL;
	fwdState->servers = fs->next;
	fwdServerFree(fs);
	fwdRestart(fwdState);
	return;
    }
#if LINUX_TPROXY
    if (fd == -1 && fwdState->request->flags.tproxy)
	fd = pconnPop(name, port, domain, &fwdState->request->client_addr, 0, NULL);
#endif
    if (fd == -1) {
	fd = pconnPop(name, port, domain, NULL, 0, &idle);
    }
    if (fd != -1) {
	if (fwdCheckRetriable(fwdState)) {
	    debug(17, 3) ("fwdConnectStart: reusing pconn FD %d\n", fd);
	    fwdState->server_fd = fd;
	    fwdState->n_tries++;
	    if (!fs->peer)
		fwdState->origin_tries++;
	    comm_add_close_handler(fd, fwdServerClosed, fwdState);
	    if (fs->peer)
		hierarchyNote(&fwdState->request->hier, fs->code, fs->peer->name);
	    else if (Config.onoff.log_ip_on_direct && fs->code == HIER_DIRECT)
		hierarchyNote(&fwdState->request->hier, fs->code, fd_table[fd].ipaddr);
	    else
		hierarchyNote(&fwdState->request->hier, fs->code, name);
	    if (fs->peer && idle >= 0 && idle < fs->peer->idle) {
		debug(17, 3) ("fwdConnectStart: Opening idle connetions for '%s'\n",
		    fs->peer->name);
		outgoing = getOutgoingAddr(fwdState->request);
		tos = getOutgoingTOS(fwdState->request);
		debug(17, 3) ("fwdConnectStart: got addr %s, tos %d\n",
		    inet_ntoa(outgoing), tos);
		idle += fs->peer->stats.idle_opening;
		while (idle < fs->peer->idle) {
		    openIdleConn(fs->peer, domain, outgoing, tos, ctimeout);
		    idle++;
		}
	    }
	    fwdDispatch(fwdState);
	    return;
	} else {
	    /* Discard the persistent connection to not cause
	     * a imbalance in number of conenctions open if there
	     * is a lot of POST requests
	     */
	    comm_close(fd);
	}
    }
#if URL_CHECKSUM_DEBUG
    assert(fwdState->entry->mem_obj->chksum == url_checksum(url));
#endif
    outgoing = getOutgoingAddr(fwdState->request);
    tos = getOutgoingTOS(fwdState->request);

    fwdState->request->out_ip = outgoing;

    debug(17, 3) ("fwdConnectStart: got addr %s, tos %d\n",
	inet_ntoa(outgoing), tos);
    fd = comm_openex(SOCK_STREAM,
	IPPROTO_TCP,
	outgoing,
	0,
	COMM_NONBLOCKING,
	tos,
	url);
    if (fd < 0) {
	debug(50, 4) ("fwdConnectStart: %s\n", xstrerror());
	err = errorCon(ERR_SOCKET_FAILURE, HTTP_INTERNAL_SERVER_ERROR, fwdState->request);
	err->xerrno = errno;
	fwdFail(fwdState, err);
	fwdStateFree(fwdState);
	return;
    }
    fwdState->server_fd = fd;
    fwdState->n_tries++;
    if (!fs->peer)
	fwdState->origin_tries++;
    /*
     * stats.conn_open is used to account for the number of
     * connections that we have open to the peer, so we can limit
     * based on the max-conn option.  We need to increment here,
     * even if the connection may fail.
     */
    if (fs->peer) {
	fs->peer->stats.conn_open++;
	comm_add_close_handler(fd, fwdPeerClosed, fs->peer);
    }
    comm_add_close_handler(fd, fwdServerClosed, fwdState);
    commSetTimeout(fd,
	ctimeout,
	fwdConnectTimeout,
	fwdState);
    if (fs->peer) {
	hierarchyNote(&fwdState->request->hier, fs->code, fs->peer->name);
    } else {
#if LINUX_TPROXY
	if (fwdState->request->flags.tproxy) {

	    itp.v.addr.faddr.s_addr = fwdState->src.sin_addr.s_addr;
	    itp.v.addr.fport = 0;

	    /* If these syscalls fail then we just fallback to connecting
	     * normally by simply ignoring the errors...
	     */
	    itp.op = TPROXY_ASSIGN;
	    if (setsockopt(fd, SOL_IP, IP_TPROXY, &itp, sizeof(itp)) == -1) {
		debug(20, 1) ("tproxy ip=%s,0x%x,port=%d ERROR ASSIGN\n",
		    inet_ntoa(itp.v.addr.faddr),
		    itp.v.addr.faddr.s_addr,
		    itp.v.addr.fport);
	    } else {
		itp.op = TPROXY_FLAGS;
		itp.v.flags = ITP_CONNECT;
		if (setsockopt(fd, SOL_IP, IP_TPROXY, &itp, sizeof(itp)) == -1) {
		    debug(20, 1) ("tproxy ip=%x,port=%d ERROR CONNECT\n",
			itp.v.addr.faddr.s_addr,
			itp.v.addr.fport);
		}
	    }
	}
#endif
	hierarchyNote(&fwdState->request->hier, fs->code, fwdState->request->host);
    }
    commConnectStart(fd, host, port, fwdConnectDone, fwdState);
}
{% endhighlight %}


{% highlight c %}
void
commConnectStart(int fd, const char *host, u_short port, CNCB * callback, void *data)
{
	printf("########commConnectStart \n");
    ConnectStateData *cs;
    debug(5, 3) ("commConnectStart: FD %d, %s:%d\n", fd, host, (int) port);
    cs = cbdataAlloc(ConnectStateData);
    cs->fd = fd;
    cs->host = xstrdup(host);
    cs->port = port;
    cs->callback = callback;
    cs->data = data;
    cbdataLock(cs->data);
    comm_add_close_handler(fd, commConnectFree, cs);
    ipcache_nbgethostbyname(host, commConnectDnsHandle, cs);
}
{% endhighlight %}

{% highlight c %}
static void
fwdConnectDone(int server_fd, int status, void *data)
{
	printf("##############fwdConnectDone \n");
    FwdState *fwdState = data;
    FwdServer *fs = fwdState->servers;
    ErrorState *err;
    request_t *request = fwdState->request;
    assert(fwdState->server_fd == server_fd);
    if (Config.onoff.log_ip_on_direct && status != COMM_ERR_DNS && fs->code == HIER_DIRECT)
	hierarchyNote(&fwdState->request->hier, fs->code, fd_table[server_fd].ipaddr);
    if (status == COMM_ERR_DNS) {
	/*
	 * Only set the dont_retry flag if the DNS lookup fails on
	 * a direct connection.  If DNS lookup fails when trying
	 * a neighbor cache, we may want to retry another option.
	 */
	if (NULL == fs->peer)
	    fwdState->flags.dont_retry = 1;
	debug(17, 4) ("fwdConnectDone: Unknown host: %s\n",
	    request->host);
	err = errorCon(ERR_DNS_FAIL, HTTP_GATEWAY_TIMEOUT, fwdState->request);
	err->dnsserver_msg = xstrdup(dns_error_message);
	fwdFail(fwdState, err);
	comm_close(server_fd);
    } else if (status != COMM_OK) {
	assert(fs);
	err = errorCon(ERR_CONNECT_FAIL, HTTP_GATEWAY_TIMEOUT, fwdState->request);
	err->xerrno = errno;
	fwdFail(fwdState, err);
	if (fs->peer)
	    peerConnectFailed(fs->peer);
	comm_close(server_fd);
    } else {
	debug(17, 3) ("fwdConnectDone: FD %d: '%s'\n", server_fd, storeUrl(fwdState->entry));
#if USE_SSL
	if ((fs->peer && fs->peer->use_ssl) ||
	    (!fs->peer && request->protocol == PROTO_HTTPS)) {
	    fwdInitiateSSL(fwdState);
	    return;
	}
#endif
	fwdDispatch(fwdState);
    }
}
{% endhighlight %}

{% highlight c %}
static void
fwdDispatch(FwdState * fwdState)
{
	printf("#########fwdDispatch \n");
    peer *p = NULL;
    request_t *request = fwdState->request;
    StoreEntry *entry = fwdState->entry;
    ErrorState *err;
    int server_fd = fwdState->server_fd;
    FwdServer *fs = fwdState->servers;
    debug(17, 3) ("fwdDispatch: FD %d: Fetching '%s %s'\n",
	fwdState->client_fd,
	RequestMethods[request->method].str,
	storeUrl(entry));
    /*
     * Assert that server_fd is set.  This is to guarantee that fwdState
     * is attached to something and will be deallocated when server_fd
     * is closed.
     */
    assert(server_fd > -1);
    /*assert(!EBIT_TEST(entry->flags, ENTRY_DISPATCHED)); */
    assert(entry->ping_status != PING_WAITING);
    assert(entry->lock_count);
    EBIT_SET(entry->flags, ENTRY_DISPATCHED);
    fd_note(server_fd, storeUrl(fwdState->entry));
    fd_table[server_fd].uses++;
    if (fd_table[server_fd].uses == 1 && fs->peer)
	peerConnectSucceded(fs->peer);
    fwdState->request->out_ip = fd_table[server_fd].local_addr;
    netdbPingSite(request->host);
    entry->mem_obj->refresh_timestamp = squid_curtime;
    if (fwdState->servers && (p = fwdState->servers->peer)) {
	p->stats.fetches++;
	fwdState->request->peer_login = p->login;
	fwdState->request->peer_domain = p->domain;
	httpStart(fwdState);
    } else {
	fwdState->request->peer_login = NULL;
	fwdState->request->peer_domain = NULL;
	switch (request->protocol) {
#if USE_SSL
	case PROTO_HTTPS:
	    httpStart(fwdState);
	    break;
#endif
	case PROTO_HTTP:
	    httpStart(fwdState);
	    break;
	case PROTO_GOPHER:
	    gopherStart(fwdState);
	    break;
	case PROTO_FTP:
	    ftpStart(fwdState);
	    break;
	case PROTO_CACHEOBJ:
	case PROTO_INTERNAL:
	case PROTO_URN:
	    fatal_dump("Should never get here");
	    break;
	case PROTO_WHOIS:
	    whoisStart(fwdState);
	    break;
	case PROTO_WAIS:	/* not implemented */
	default:
	    debug(17, 1) ("fwdDispatch: Cannot retrieve '%s'\n",
		storeUrl(entry));
	    err = errorCon(ERR_UNSUP_REQ, HTTP_BAD_REQUEST, fwdState->request);
	    fwdFail(fwdState, err);
	    /*
	     * Force a persistent connection to be closed because
	     * some Netscape browsers have a bug that sends CONNECT
	     * requests as GET's over persistent connections.
	     */
	    request->flags.proxy_keepalive = 0;
	    /*
	     * Set the dont_retry flag becuase this is not a
	     * transient (network) error; its a bug.
	     */
	    fwdState->flags.dont_retry = 1;
	    comm_close(fwdState->server_fd);
	    break;
	}
    }
}
{% endhighlight %}

{% highlight c %}
void
httpStart(FwdState * fwd)
{
	printf("###########httpStart \n");
    int fd = fwd->server_fd;
    HttpStateData *httpState;
    request_t *proxy_req;
    request_t *orig_req = fwd->request;
    debug(11, 3) ("httpStart: \"%s %s\"\n",
	RequestMethods[orig_req->method].str,
	storeUrl(fwd->entry));
    httpState = cbdataAlloc(HttpStateData);
    storeLockObject(fwd->entry);
    httpState->fwd = fwd;
    httpState->entry = fwd->entry;
    httpState->fd = fd;
    if (fwd->servers)
	httpState->peer = fwd->servers->peer;	/* might be NULL */
    if (httpState->peer) {
	const char *url;
	if (httpState->peer->options.originserver)
	    url = strBuf(orig_req->urlpath);
	else
	    url = storeUrl(httpState->entry);
	proxy_req = requestCreate(orig_req->method,
	    orig_req->protocol, url);
	xstrncpy(proxy_req->host, httpState->peer->host, SQUIDHOSTNAMELEN);
	proxy_req->port = httpState->peer->http_port;
	proxy_req->flags = orig_req->flags;
	proxy_req->lastmod = orig_req->lastmod;
	httpState->request = requestLink(proxy_req);
	httpState->orig_request = requestLink(orig_req);
	proxy_req->flags.proxying = 1;
	/*
	 * This NEIGHBOR_PROXY_ONLY check probably shouldn't be here.
	 * We might end up getting the object from somewhere else if,
	 * for example, the request to this neighbor fails.
	 */
	if (httpState->peer->options.proxy_only)
	    storeReleaseRequest(httpState->entry);
#if DELAY_POOLS
	assert(delayIsNoDelay(fd) == 0);
	if (httpState->peer->options.no_delay)
	    delaySetNoDelay(fd);
#endif
    } else {
	httpState->request = requestLink(orig_req);
	httpState->orig_request = requestLink(orig_req);
    }
    /*
     * register the handler to free HTTP state data when the FD closes
     */
    comm_add_close_handler(fd, httpStateFree, httpState);
    statCounter.server.all.requests++;
    statCounter.server.http.requests++;
    httpSendRequest(httpState);
    /*
     * We used to set the read timeout here, but not any more.
     * Now its set in httpSendComplete() after the full request,
     * including request body, has been written to the server.
     */
}
{% endhighlight %}


{% highlight c %}
/* This will be called when connect completes. Write request. */
static void
httpSendRequest(HttpStateData * httpState)
{
	printf("###########httpSendRequest \n");
    MemBuf mb;
    request_t *req = httpState->request;
    StoreEntry *entry = httpState->entry;
    peer *p = httpState->peer;
    CWCB *sendHeaderDone;
    int fd = httpState->fd;

    debug(11, 5) ("httpSendRequest: FD %d: httpState %p.\n", fd, httpState);

    /* Schedule read reply. (but no timeout set until request fully sent) */
    commSetTimeout(fd, Config.Timeout.lifetime, httpTimeout, httpState);
    commSetSelect(fd, COMM_SELECT_READ, httpReadReply, httpState, 0);

    if (httpState->orig_request->body_reader)
	sendHeaderDone = httpSendRequestEntry;
    else
	sendHeaderDone = httpSendComplete;

    if (p != NULL) {
	if (p->options.originserver)
	    httpState->flags.originpeer = 1;
	else
	    httpState->flags.proxying = 1;
    } else {
	httpState->flags.proxying = 0;
	httpState->flags.originpeer = 0;
    }
    /*
     * Is keep-alive okay for all request methods?
     */
    if (!Config.onoff.server_pconns)
	httpState->flags.keepalive = 0;
    else if (p == NULL)
	httpState->flags.keepalive = 1;
    else if (p->stats.n_keepalives_sent < 10)
	httpState->flags.keepalive = 1;
    else if ((double) p->stats.n_keepalives_recv / (double) p->stats.n_keepalives_sent > 0.50)
	httpState->flags.keepalive = 1;
    if (httpState->peer) {
	if (neighborType(httpState->peer, httpState->request) == PEER_SIBLING &&
	    !httpState->peer->options.allow_miss)
	    httpState->flags.only_if_cached = 1;
	httpState->flags.front_end_https = httpState->peer->front_end_https;
    }
    if (httpState->peer)
	httpState->flags.http11 = httpState->peer->options.http11;
    else
	httpState->flags.http11 = Config.onoff.server_http11;
    memBufDefInit(&mb);
    httpBuildRequestPrefix(req,
	httpState->orig_request,
	entry,
	&mb,
	httpState->flags);
    if (req->flags.pinned)
	httpState->flags.keepalive = 1;
    debug(11, 6) ("httpSendRequest: FD %d:\n%s\n", fd, mb.buf);
    comm_write_mbuf(fd, mb, sendHeaderDone, httpState);
}
{% endhighlight %}


{% highlight c %}
/* a wrapper around comm_write to allow for MemBuf to be comm_written in a snap */
void
comm_write_mbuf(int fd, MemBuf mb, CWCB * handler, void *handler_data)
{
	printf("#############comm_write_mbuf\n");
    comm_write(fd, mb.buf, mb.size, handler, handler_data, memBufFreeFunc(&mb));
}
{% endhighlight %}



{% highlight c %}
/* Select for Writing on FD, until SIZE bytes are sent.  Call
 * *HANDLER when complete. */
void
comm_write(int fd, const char *buf, int size, CWCB * handler, void *handler_data, FREE * free_func)
{
	printf("###########comm_write \n");
    CommWriteStateData *state = &fd_table[fd].rwstate;
    debug(5, 5) ("comm_write: FD %d: sz %d: hndl %p: data %p.\n",
	fd, size, handler, handler_data);
    if (state->valid) {
	debug(5, 1) ("comm_write: fd_table[%d].rwstate.valid == true!\n", fd);
	fd_table[fd].rwstate.valid = 0;
    }
    state->buf = (char *) buf;
    state->size = size;
    state->header_size = 0;
    state->offset = 0;
    state->handler = handler;
    state->handler_data = handler_data;
    state->free_func = free_func;
    state->valid = 1;
    cbdataLock(handler_data);
    commSetSelect(fd, COMM_SELECT_WRITE, commHandleWrite, NULL, 0);
}
{% endhighlight %}


{% highlight c %}
/* Write to FD. */
static void
commHandleWrite(int fd, void *data)
{
	printf("############commHandleWrite \n");
    int len = 0;
    int nleft;
    CommWriteStateData *state = &fd_table[fd].rwstate;

    assert(state->valid);

    debug(5, 5) ("commHandleWrite: FD %d: off %ld, hd %ld, sz %ld.\n",
	fd, (long int) state->offset, (long int) state->header_size, (long int) state->size);

    nleft = state->size + state->header_size - state->offset;
    if (state->offset < state->header_size)
	len = FD_WRITE_METHOD(fd, state->header + state->offset, state->header_size - state->offset);
    else
	len = FD_WRITE_METHOD(fd, state->buf + state->offset - state->header_size, nleft);
    debug(5, 5) ("commHandleWrite: write() returns %d\n", len);
    fd_bytes(fd, len, FD_WRITE);
    statCounter.syscalls.sock.writes++;

    if (len == 0) {
	/* Note we even call write if nleft == 0 */
	/* We're done */
	if (nleft != 0)
	    debug(5, 1) ("commHandleWrite: FD %d: write failure: connection closed with %d bytes remaining.\n", fd, nleft);
	CommWriteStateCallbackAndFree(fd, nleft ? COMM_ERROR : COMM_OK);
    } else if (len < 0) {
	/* An error */
	if (fd_table[fd].flags.socket_eof) {
	    debug(5, 2) ("commHandleWrite: FD %d: write failure: %s.\n",
		fd, xstrerror());
	    CommWriteStateCallbackAndFree(fd, COMM_ERROR);
	} else if (ignoreErrno(errno)) {
	    debug(5, 10) ("commHandleWrite: FD %d: write failure: %s.\n",
		fd, xstrerror());
	    commSetSelect(fd,
		COMM_SELECT_WRITE,
		commHandleWrite,
		NULL,
		0);
	} else {
	    debug(5, 2) ("commHandleWrite: FD %d: write failure: %s.\n",
		fd, xstrerror());
	    CommWriteStateCallbackAndFree(fd, COMM_ERROR);
	}
    } else {
	/* A successful write, continue */
	state->offset += len;
	if (state->offset < state->size + state->header_size) {
	    /* Not done, reinstall the write handler and write some more */
	    commSetSelect(fd,
		COMM_SELECT_WRITE,
		commHandleWrite,
		NULL,
		0);
	} else {
	    CommWriteStateCallbackAndFree(fd, COMM_OK);
	}
    }
}
{% endhighlight %}

{% highlight c %}
static void
CommWriteStateCallbackAndFree(int fd, int code)
{
	printf("###########CommWriteStateCallbackAndFree \n");
    CommWriteStateData *CommWriteState = &fd_table[fd].rwstate;
    CWCB *callback = NULL;
    void *data;
    if (!CommWriteState->valid) {
	return;
    }
    CommWriteState->valid = 0;
    if (CommWriteState->free_func) {
	FREE *free_func = CommWriteState->free_func;
	void *free_buf = CommWriteState->buf;
	CommWriteState->free_func = NULL;
	CommWriteState->buf = NULL;
	free_func(free_buf);
    }
    callback = CommWriteState->handler;
    data = CommWriteState->handler_data;
    CommWriteState->handler = NULL;
    CommWriteState->valid = 0;
    if (callback && cbdataValid(data))
	callback(fd, CommWriteState->buf, CommWriteState->offset, code, data);
    cbdataUnlock(data);
}
{% endhighlight %}





