---
layout: post
title: Squid定制开发(二)之怎样在不影响业务的情况下重新加载hosts文件(增量模式)
---

Squid定制开发(二)之怎样在不影响业务的情况下重新加载hosts文件(增量模式)
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2013/08/02/squid_reconfig2.html


接上文，如果考虑到hosts文件很大的情况下，前面的替换方案效率可能会有影响。所以引入增量方式，具体来说：

{% highlight java %}
假设 hosts文件内容如下
[root@miaohong squiddiff]# cat etc/hosts
192.168.3.9 s4
192.168.1.19 s1
192.168.2.12 s2

更新的文件为hosts_new
[root@miaohong squiddiff]# cat  etc/hosts_new
192.168.3.9 s8
192.168.2.12 s2
192.168.4.11 s19


首先将上面两个文件进行排序
[root@miaohong squiddiff]# sort etc/hosts
192.168.1.19 s1
192.168.2.12 s2
192.168.3.9 s4

[root@miaohong squiddiff]# sort etc/hosts_new
192.168.2.12 s2
192.168.3.9 s8
192.168.4.11 s19

上面排序后的两个文件 分别命名为 hosts_sort  和  hosts_new_sort

对hosts_sort  和  hosts_new_sort 做comm运算

对于增加：
[root@miaohong squiddiff]# comm -13 etc/hosts_sort etc/hosts_new_sort
192.168.3.9 s8
192.168.4.11 s19

生成文件命名为hosts_add， 即为要增加的文件内容


对于删除：
[root@miaohong squiddiff]# comm -23 etc/hosts_sort etc/hosts_new_sort
192.168.1.19 s1
192.168.3.9 s4

生成文件命名为hosts_del， 即为要删除的文件内容

{% endhighlight %}

贴一个diff吧

{% highlight java %}
Index: src/fqdncache.c
===================================================================
--- src/fqdncache.c	(revision 101206)
+++ src/fqdncache.c	(working copy)
@@ -565,6 +565,42 @@
     purge_entries_fromhosts();
 }
 
+//add by miaohong
+
+void fqdncacheDel(const char *name)
+{
+	fqdncache_entry * fqdndelEntry;
+	if(fqdndelEntry=fqdncache_get(name)) {
+		fqdncacheRelease(fqdndelEntry);
+	}
+}
+
+
+void
+debug_walkfqdntables() 
+{	
+	int i;
+	hash_table *hfqdn = fqdn_table;
+	hash_link *walker = NULL;
+	debug(35, 1) ("-----fqdn_table->count = %d ------- \n",
+	    hfqdn->count);
+	/*
+	debug(35, 1) ("---------hashkey_count = %d------\n",
+	    hashkey_count);	
+	debug(35, 1) ("walking hash table...\n");	
+	for (i = 0; i < hashkey_count; i++) {
+		walker = hfqdn->buckets[hashkey[i]];
+		debug(14, 1) ("item %5d: key: '%s' \n",
+	    i, walker->key);	
+	}
+	debug(35, 1) ("done walking hash table...\n");
+	*/
+}
+
+
+//add by miaohong end
+
+
 /*
  *  adds a "static" entry from /etc/hosts.  the worldist is to be
  *  managed by the caller, including pointed-to strings
Index: src/ipcache.c
===================================================================
--- src/ipcache.c	(revision 101211)
+++ src/ipcache.c	(working copy)
@@ -759,21 +759,29 @@
 }
 
 //add by miaohong
-int hashkey[];
-static int hashkey_count = 0;
+/*
+int hashkey[] ={0};
+int hashkey_count = 0;
+*/
 
-void initPara()
+void ipcacheDel(const char *addrname)
 {
-	hashkey_count = 0;
+	ipcache_entry * ipdelEntry;
+	int b;
+	if(ipdelEntry=ipcache_get(addrname)) {
+		ipcacheRelease(ipdelEntry);
+		//b = ip_table->hash(hostname, hid->size);
+		//hashkey_count--;
+	}
 }
 
-void
-releaseIptable()
+/*
+void initPara()
 {
-	hashFreeItems(ip_table, ipcacheFreeEntry);
+	hashkey_count = 0;
 }
+*/
 
-
 void
 debug_walkIptables() 
 {	
@@ -780,19 +788,21 @@
 	int i;
 	hash_table *hid = ip_table;
 	hash_link *walker = NULL;
-	debug(14, 1) ("-----ip_table->count = %d ------- \n",
-	    hid->count);
-	debug(14, 1) ("---------hashkey_count = %d------\n",
-	    hashkey_count);	
+	debug(14, 1) ("-----ip_table->count = %d ------- \n",hid->count);
+	/*
+	debug(14, 1) ("---------hashkey_count = %d------\n",hashkey_count);	
 	debug(14, 1) ("walking hash table...\n");	
+	
 	for (i = 0; i < hashkey_count; i++) {
 		walker = hid->buckets[hashkey[i]];
-		debug(14, 1) ("item %5d: key: '%s' \n",
-	    i, walker->key);	
+		debug(14, 1) ("item %5d: key: '%s' \n",i, walker->key);	
 	}
+	
 	debug(14, 1) ("done walking hash table...\n");
+	*/
 }
 
+/*
 void
 genHashkey(hash_table *hid, const char *name)
 {
@@ -800,9 +810,11 @@
 	b = hid->hash(name, hid->size);
 	hashkey[hashkey_count] = b;	
 	hashkey_count++;
-}
+} 
+*/
 
 //add by miaohong end
+
 /*
  *  adds a "static" entry from /etc/hosts.  
  *  returns 0 upon success, 1 if the ip address is invalid
@@ -844,10 +856,9 @@
     ipcacheAddEntry(i);
     ipcacheLockEntry(i);
 	//add by miaohong
-	genHashkey(ip_table, name);
+	//genHashkey(ip_table, name);
 	//debug_walkIptables();
 	//add by miaohong end
-	printf("---------------end--------------\n");
     return 0;
 }
 
Index: src/stat.c
===================================================================
--- src/stat.c	(revision 101206)
+++ src/stat.c	(working copy)
@@ -1471,23 +1471,32 @@
 }
 
 //add by mh
+/*
 static void releaseSource()
 {
 	ipcacheFreeMemory();
 	fqdncacheFreeMemory();
 }
+*/
+static void debugReconfig()
+{
+    debug_walkIptables();
+	debug_walkfqdntables();
+}
+
 static void
 doReconfig(StoreEntry * s)
 {
-	initPara();
-	//prevent memory leaks
-	releaseSource();
-	ipcache_init(); 
-	fqdncache_init();
-	parseEtcHosts();
-	debug_walkIptables();
+	debugReconfig();
+	debug(18, 1) ("[ADD] hosts to be add...\n");
+	parseDiffHostsAdd();
+	debugReconfig();
+	debug(18, 1) ("[DEL] hosts to be del...\n");
+	parseDiffHostsDel();
+	debugReconfig();
 }
 //add by mh end 
+
 static void
 statClientRequests(StoreEntry * s)
 {
Index: src/tools.c
===================================================================
--- src/tools.c	(revision 101206)
+++ src/tools.c	(working copy)
@@ -1137,7 +1137,159 @@
     return 1;
 }
 
+//miaohong add
+
+#define DIFF_HOSTS_ADD "/opt/squiddiff/etc/hosts_add"
+#define DIFF_HOSTS_DEL "/opt/squiddiff/etc/hosts_del"
+
+
 void
+parseDiffHostsDel(void)
+{
+    FILE *fp;
+    char buf[1024];
+    char buf2[512];
+    char *nt = buf;
+    char *lt = buf;
+	/*
+    if (NULL == Config.etcHostsPath)
+	return;
+    if (0 == strcmp(Config.etcHostsPath, "none"))
+	return;
+	*/
+    fp = fopen(DIFF_HOSTS_DEL, "r");
+    if (fp == NULL) {
+	debug(1, 1) ("parseDiffHostsDel: %s: %s\n",
+	    DIFF_HOSTS_DEL, xstrerror());
+	return;
+    }
+#ifdef _SQUID_WIN32_
+    setmode(fileno(fp), O_TEXT);
+#endif
+    while (fgets(buf, 1024, fp)) {	/* for each line */
+	wordlist *hosts = NULL;
+	char *addr;
+	if (buf[0] == '#')	/* MS-windows likes to add comments */
+	    continue;
+	strtok(buf, "#");	/* chop everything following a comment marker */
+	lt = buf;
+	addr = buf;
+	debug(1, 5) ("etc_hosts: line is '%s'\n", buf);
+	nt = strpbrk(lt, w_space);
+	if (nt == NULL)		/* empty line */
+	    continue;
+	*nt = '\0';		/* null-terminate the address */
+	debug(1, 5) ("etc_hosts: address is '%s'\n", addr);
+	lt = nt + 1;
+	while ((nt = strpbrk(lt, w_space))) {
+	    char *host = NULL;
+	    if (nt == lt) {	/* multiple spaces */
+		debug(1, 5) ("etc_hosts: multiple spaces, skipping\n");
+		lt = nt + 1;
+		continue;
+	    }
+	    *nt = '\0';
+	    debug(1, 5) ("etc_hosts: got hostname '%s'\n", lt);
+	    if (Config.appendDomain && !strchr(lt, '.')) {
+		/* I know it's ugly, but it's only at reconfig */
+		strncpy(buf2, lt, 512);
+		strncat(buf2, Config.appendDomain, 512 - strlen(lt) - 1);
+		host = buf2;
+	    } else {
+		host = lt;
+	    }
+		ipcacheDel(host);
+
+	    //if (ipcacheAddEntryFromHosts(host, addr) != 0)
+		//goto skip;	/* invalid address, continuing is useless */
+	    //wordlistAdd(&hosts, host);
+	    lt = nt + 1;
+		
+	}
+	//ipcacheDel(addr);
+	fqdncacheDel(addr);
+	/*
+	fqdncacheAddEntryFromHosts(addr, hosts);
+      skip:
+	wordlistDestroy(&hosts);
+	*/
+    }
+    fclose(fp);
+}
+
+
+
+void
+parseDiffHostsAdd(void)
+{
+    FILE *fp;
+    char buf[1024];
+    char buf2[512];
+    char *nt = buf;
+    char *lt = buf;
+	/*
+    if (NULL == Config.etcHostsPath)
+	return;
+    if (0 == strcmp(Config.etcHostsPath, "none"))
+	return;
+	*/
+    fp = fopen(DIFF_HOSTS_ADD, "r");
+    if (fp == NULL) {
+	debug(1, 1) ("parseDiffHostsAdd: %s: %s\n",
+	    DIFF_HOSTS_ADD, xstrerror());
+	return;
+    }
+#ifdef _SQUID_WIN32_
+    setmode(fileno(fp), O_TEXT);
+#endif
+    while (fgets(buf, 1024, fp)) {	/* for each line */
+	wordlist *hosts = NULL;
+	char *addr;
+	if (buf[0] == '#')	/* MS-windows likes to add comments */
+	    continue;
+	strtok(buf, "#");	/* chop everything following a comment marker */
+	lt = buf;
+	addr = buf;
+	debug(1, 5) ("etc_hosts: line is '%s'\n", buf);
+	nt = strpbrk(lt, w_space);
+	if (nt == NULL)		/* empty line */
+	    continue;
+	*nt = '\0';		/* null-terminate the address */
+	debug(1, 5) ("etc_hosts: address is '%s'\n", addr);
+	lt = nt + 1;
+	while ((nt = strpbrk(lt, w_space))) {
+	    char *host = NULL;
+	    if (nt == lt) {	/* multiple spaces */
+		debug(1, 5) ("etc_hosts: multiple spaces, skipping\n");
+		lt = nt + 1;
+		continue;
+	    }
+	    *nt = '\0';
+	    debug(1, 5) ("etc_hosts: got hostname '%s'\n", lt);
+	    if (Config.appendDomain && !strchr(lt, '.')) {
+		/* I know it's ugly, but it's only at reconfig */
+		strncpy(buf2, lt, 512);
+		strncat(buf2, Config.appendDomain, 512 - strlen(lt) - 1);
+		host = buf2;
+	    } else {
+		host = lt;
+	    }
+	    if (ipcacheAddEntryFromHosts(host, addr) != 0)
+		goto skip;	/* invalid address, continuing is useless */
+	    wordlistAdd(&hosts, host);
+	    lt = nt + 1;
+	}
+	fqdncacheAddEntryFromHosts(addr, hosts);
+      skip:
+	wordlistDestroy(&hosts);
+    }
+    fclose(fp);
+}
+
+//miaohong add end

{% endhighlight %}


