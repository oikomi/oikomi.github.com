---
layout: post
title: Squid定制开发(一)之怎样在不影响业务的情况下重新加载hosts文件
---

Squid定制开发(一)之怎样在不影响业务的情况下重新加载hosts文件
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2013/07/29/squid_reconfig.html


最近我做的项目遇到一个需求，就是squid要经常重新读取hosts文件，之前的方案一直是 squid -k reconfigure 去重加载。但是这样做有很大的问题。

看了一下代码， 发现squid这块做的很糟糕（不如nginx），如下

{% highlight java %}
void
clientHttpConnectionsClose(void)
{
    int i = 0;
    if (opt_stdin_overrides_http_port && reconfiguring)
         i++;                     /* skip closing & reopening first port because it is overridden */
    for (; i < NHttpSockets; i++) {
         if (HttpSockets[i] >= 0) {
             debug(1, 1) ("FD %d Closing HTTP connection\n", HttpSockets[i]);
             comm_close(HttpSockets[i]);
             HttpSockets[i] = -1;
         }
    }
    NHttpSockets = 0;
}
{% endhighlight %}

发现squid会把所有客户端连接都干掉的。如果加载频繁，感觉明显会影响业务的。

解决思路：

借鉴squidclient给squid发送一个命令，squid接收到该命令后，就去读取hosts文件，再去刷新内存变量。

如  squidclient -t 1 -h 127.0.0.1 -p 18000 mgr:reconfig  其中reconfig就是自己定义的命令。

上面的方案可以在不断开客户端连接的情况下，起到重新加载配置的作用。


代码改动如下：

在src/stat.c中

{% highlight java %}
//add by mh
static OBJH doReconfig;
//add by mh end

//add by mh
static void releaseSource()
{
	ipcacheFreeMemory();
	fqdncacheFreeMemory();
}

static void
doReconfig(StoreEntry * s)
{
	//prevent memory leaks
	releaseSource();
	ipcache_init(); 
	fqdncache_init();
	parseEtcHosts();
	debug_walkIptables();
}
//add by mh end 
{% endhighlight %}


{% highlight java %}
void
statInit(void)
{
    int i;
    debug(18, 5) ("statInit: Initializing...\n");
    CBDATA_INIT_TYPE(StatObjectsState);
    for (i = 0; i < N_COUNT_HIST; i++)
	statCountersInit(&CountHist[i]);
    for (i = 0; i < N_COUNT_HOUR_HIST; i++)
	statCountersInit(&CountHourHist[i]);
    statCountersInit(&statCounter);
    eventAdd("statAvgTick", statAvgTick, NULL, (double) COUNT_INTERVAL, 1);
    cachemgrRegister("info",
	"General Runtime Information",
	info_get, 0, 1);
    cachemgrRegister("filedescriptors",
	"Process Filedescriptor Allocation",
	statFiledescriptors, 0, 1);
    cachemgrRegister("objects",
	"All Cache Objects",
	stat_objects_get, 0, 0);
    cachemgrRegister("vm_objects",
	"In-Memory and In-Transit Objects",
	stat_vmobjects_get, 0, 0);
    cachemgrRegister("openfd_objects",
	"Objects with Swapout files open",
	statOpenfdObj, 0, 0);
    cachemgrRegister("pending_objects",
	"Objects being retreived from the network",
	statPendingObj, 0, 0);
    cachemgrRegister("client_objects",
	"Objects being sent to clients",
	statClientsObj, 0, 0);
    cachemgrRegister("io",
	"Server-side network read() size histograms",
	stat_io_get, 0, 1);
    cachemgrRegister("counters",
	"Traffic and Resource Counters",
	statCountersDump, 0, 1);
    cachemgrRegister("peer_select",
	"Peer Selection Algorithms",
	statPeerSelect, 0, 1);
    cachemgrRegister("digest_stats",
	"Cache Digest and ICP blob",
	statDigestBlob, 0, 1);
    cachemgrRegister("5min",
	"5 Minute Average of Counters",
	statAvg5min, 0, 1);
    cachemgrRegister("60min",
	"60 Minute Average of Counters",
	statAvg60min, 0, 1);
    cachemgrRegister("utilization",
	"Cache Utilization",
	statUtilization, 0, 1);
#if STAT_GRAPHS
    cachemgrRegister("graph_variables",
	"Display cache metrics graphically",
	statGraphDump, 0, 1);
#endif
    cachemgrRegister("histograms",
	"Full Histogram Counts",
	statCountersHistograms, 0, 1);
    ClientActiveRequests.head = NULL;
    ClientActiveRequests.tail = NULL;
    cachemgrRegister("active_requests",
	"Client-side Active Requests",
	statClientRequests, 0, 1);
	//add by mh for reconfig
	cachemgrRegister("reconfig",
		"reconfig config file",
		doReconfig, 0, 1);
	//add by mh for reconfig end
}
{% endhighlight %}

其中debug_walkIptables是调试打印现在的hosts内容

{% highlight java %}
void
debug_walkIptables() 
{	
	int i;
	hash_table *hid = ip_table;
	hash_link *walker = NULL;
	printf("-----ip_table->count = %d ------- \n", hid->count);
	printf("---------hashkey_count = %d------\n", hashkey_count);
	printf("walking hash table...\n");
	for (i = 0; i < hashkey_count; i++) {
		walker = hid->buckets[hashkey[i]];
		printf("item %5d: key: '%s' \n", i, walker->key);
	}
	printf("done walking hash table...\n");
}
{% endhighlight %}
