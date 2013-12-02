---
layout: post
title: Squid定制开发(三)之添加修改header头
---

Squid定制开发(三)之添加修改header头
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2013/12/01/squid_addheader.html


最近有个需求，需要：
源站会输出一个”Cache-Control c-maxage=xxx”的响应头，要求我们的CDN上遇到这样的信息，在CDN缓存仍然遵循”Cache-Control max-age=xxx”前提下，将”Cache-Control c-maxage=xxx”的内容转换为相应”Cache-Control max-age=xxx”, 输出给客户端缓存

懒得写了，贴diff吧

{% highlight java %}


*** src\client_side.c 2013-11-29 18:50:29.000000000 +-0800
--- src\client_side.c 2010-02-14 08:46:25.000000000 +-0800
***************
*** 1773,1787 ****
      HttpHeader *hdr = &rep->header;
      request_t *request = http->request;
      httpHeaderDelById(hdr, HDR_PROXY_CONNECTION);
      /* here: Keep-Alive is a field-name, not a connection directive! */
      httpHeaderDelById(hdr, HDR_KEEP_ALIVE);
      /* remove Set-Cookie if a hit */
- 	//miaohong add	
- 	m_httpHeaderPutCc(hdr, http->request->cache_control);
- 	
      if (http->flags.hit)
  	httpHeaderDelById(hdr, HDR_SET_COOKIE);
      httpHeaderDelById(hdr, HDR_TRAILER);
      httpHeaderDelById(hdr, HDR_TRANSFER_ENCODING);
      httpHeaderDelById(hdr, HDR_UPGRADE);
      /* handle Connection header */
--- 1773,1784 ----
***************
*** 1964,1981 ****
       * but X-Request-URI is likely to be the very last header to ease use from a
       * debugger [hdr->entries.count-1].
       */
      httpHeaderPutStr(hdr, HDR_X_REQUEST_URI,
  	http->entry->mem_obj->url ? http->entry->mem_obj->url : http->uri);
  #endif
- 	//miaohong add
- 	//if(httpHeaderHas(hdr,HDR_CACHE_CONTROL))
- 	//{
- 		//printf("HDR_CACHE_CONTROL exist \n");
- 	//}
- 	//printf("httpHeaderGetCc : %d---\n",httpHeaderGetCc(hdr)->c_maxage);
      httpHdrMangleList(hdr, request);
  }
  
  /* Used exclusively by clientCloneReply() during failure cases only */
  static void
  clientUnwindReply(clientHttpRequest * http, HttpReply * rep)
--- 1961,1972 ----
***************
*** 2758,2771 ****
   * such, writes processed message to the client's socket
   */
  static void
  clientSendHeaders(void *data, HttpReply * rep)
  {
      clientHttpRequest *http = data;
- 	//miaohong add
- 	//printf("cc cmax: %d-----------\n",http->request->cache_control->c_maxage);
      StoreEntry *entry = http->entry;
      ConnStateData *conn = http->conn;
      int fd = conn->fd;
      assert(http->request != NULL);
      dlinkDelete(&http->active, &ClientActiveRequests);
      dlinkAdd(http, &http->active, &ClientActiveRequests);
--- 2749,2760 ----
***************
*** 3485,3503 ****
      }
      debug(33, 3) ("clientProcessRequest2: default HIT\n");
      http->entry = e;
      return LOG_TCP_HIT;
  }
  
- 
- 
  static void
  clientProcessRequest(clientHttpRequest * http)
  {
- 	//miaohong add
- 	//printf("-----in clientProcessRequest---\n");
      char *url = http->uri;
      request_t *r = http->request;
      HttpReply *rep;
      debug(33, 4) ("clientProcessRequest: %s '%s'\n",
  	RequestMethods[r->method].str,
  	url);
--- 3474,3488 ----
***************
*** 3936,3949 ****
   * =0 : couldn't consume anything this trip (partial request); stop parsing & read more data
   * <0 : error; stop parsing
   */
  static int
  clientTryParseRequest(ConnStateData * conn)
  {
- 	//add miaohong
- 	//printf("------in clientTryParseRequest----\n");
      int fd = conn->fd;
      int nrequests;
      dlink_node *n;
      clientHttpRequest *http = NULL;
      method_t method;
      ErrorState *err = NULL;
--- 3921,3932 ----
***************
*** 4149,4161 ****
      return http->req_sz;
  }
  
  static void
  clientReadRequest(int fd, void *data)
  {
- 	//printf("--------in clientReadRequest-------\n");
      ConnStateData *conn = data;
      int size;
      fde *F = &fd_table[fd];
      int len = conn->in.size - conn->in.offset - 1;
      int ret;
      debug(33, 4) ("clientReadRequest: FD %d: reading request...\n", fd);
--- 4132,4143 ----
*** src\enums.h 2013-11-29 16:03:49.000000000 +-0800
--- src\enums.h 2009-06-26 06:48:37.000000000 +-0800
***************
*** 276,289 ****
      CC_NO_STORE,
      CC_NO_TRANSFORM,
      CC_MUST_REVALIDATE,
      CC_PROXY_REVALIDATE,
      CC_MAX_AGE,
      CC_S_MAXAGE,
-     //miaohong add
-     CC_C_MAXAGE,
      CC_MAX_STALE,
      CC_ONLY_IF_CACHED,
      CC_STALE_WHILE_REVALIDATE,
      CC_STALE_IF_ERROR,
      CC_OTHER,
      CC_ENUM_END
--- 276,287 ----
*** src\HttpHdrCc.c 2013-11-29 18:37:13.000000000 +-0800
--- src\HttpHdrCc.c 2008-05-05 07:23:13.000000000 +-0800
***************
*** 45,58 ****
      {"no-transform", CC_NO_TRANSFORM},
      {"must-revalidate", CC_MUST_REVALIDATE},
      {"proxy-revalidate", CC_PROXY_REVALIDATE},
      {"only-if-cached", CC_ONLY_IF_CACHED},
      {"max-age", CC_MAX_AGE},
      {"s-maxage", CC_S_MAXAGE},
-     //miaohong add
-     {"c-maxage", CC_C_MAXAGE},
      {"max-stale", CC_MAX_STALE},
      {"stale-while-revalidate", CC_STALE_WHILE_REVALIDATE},
      {"stale-if-error", CC_STALE_IF_ERROR},
      {"Other,", CC_OTHER}	/* ',' will protect from matches */
  };
  HttpHeaderFieldInfo *CcFieldsInfo = NULL;
--- 45,56 ----
***************
*** 79,92 ****
  /* implementation */
  
  HttpHdrCc *
  httpHdrCcCreate(void)
  {
      HttpHdrCc *cc = memAllocate(MEM_HTTP_HDR_CC);
! 	// miaohong modify
!     cc->max_age = cc->s_maxage = cc->c_maxage = cc->max_stale = cc->stale_if_error - 1;
      return cc;
  }
  
  /* creates an cc object from a 0-terminating string */
  HttpHdrCc *
  httpHdrCcParseCreate(const String * str)
--- 77,89 ----
  /* implementation */
  
  HttpHdrCc *
  httpHdrCcCreate(void)
  {
      HttpHdrCc *cc = memAllocate(MEM_HTTP_HDR_CC);
!     cc->max_age = cc->s_maxage = cc->max_stale = cc->stale_if_error - 1;
      return cc;
  }
  
  /* creates an cc object from a 0-terminating string */
  HttpHdrCc *
  httpHdrCcParseCreate(const String * str)
***************
*** 146,166 ****
  	    if (!p || !httpHeaderParseInt(p, &cc->s_maxage)) {
  		debug(65, 2) ("httpHdrCcParseInit: invalid s-maxage specs near '%s'\n", item);
  		cc->s_maxage = -1;
  		EBIT_CLR(cc->mask, type);
  	    }
  	    break;
- 	//miaohong add
- 	case CC_C_MAXAGE:
- 	    if (!p || !httpHeaderParseInt(p, &cc->c_maxage)) {
- 		debug(65, 2) ("httpHdrCcParseInit: invalid c-maxage specs near '%s'\n", item);
- 		cc->c_maxage = -1;
- 		EBIT_CLR(cc->mask, type);
- 	    }
- 	    break;
- 		
  	case CC_MAX_STALE:
  	    if (!p) {
  		debug(65, 3) ("httpHdrCcParseInit: max-stale directive is valid without value\n");
  		cc->max_stale = -1;
  	    } else if (!httpHeaderParseInt(p, &cc->max_stale)) {
  		debug(65, 2) ("httpHdrCcParseInit: invalid max-stale specs near '%s'\n", item);
--- 143,154 ----
***************
*** 210,265 ****
      HttpHdrCc *dup;
      assert(cc);
      dup = httpHdrCcCreate();
      dup->mask = cc->mask;
      dup->max_age = cc->max_age;
      dup->s_maxage = cc->s_maxage;
- 	//miaohong modify
- 	dup->c_maxage = cc->c_maxage;
      dup->max_stale = cc->max_stale;
      return dup;
  }
- 
- //miaohong add
- 
- void
- m_httpHdrCcPackInto(const HttpHdrCc * cc, Packer * p)
- {
-     http_hdr_cc_type flag;
-     int pcount = 0;
-     assert(cc && p);
-     for (flag = 0; flag < CC_ENUM_END; flag++) {
- 	if (EBIT_TEST(cc->mask, flag) && flag != CC_OTHER && flag != CC_C_MAXAGE) {
- 
- 	    /* print option name */
- 	    packerPrintf(p, (pcount ? ", %s" : "%s"), strBuf(CcFieldsInfo[flag].name));
- 
- 	    /* handle options with values */
- 	    if (flag == CC_MAX_AGE)
- 		packerPrintf(p, "=%d", (int) cc->c_maxage);
- 
- 	    if (flag == CC_S_MAXAGE)
- 		packerPrintf(p, "=%d", (int) cc->s_maxage);
- 		// miaohong add
- 	    //if (flag == CC_C_MAXAGE)
- 		//packerPrintf(p, "=%d", (int) cc->c_maxage);
- 		
- 	    if (flag == CC_MAX_STALE && cc->max_stale >= 0)
- 		packerPrintf(p, "=%d", (int) cc->max_stale);
- 
- 	    if (flag == CC_STALE_WHILE_REVALIDATE)
- 		packerPrintf(p, "=%d", (int) cc->stale_while_revalidate);
- 
- 	    pcount++;
- 	}
-     }
-     if (strLen(cc->other))
- 	packerPrintf(p, (pcount ? ", %s" : "%s"), strBuf(cc->other));
- }
- 
- 
  
  void
  httpHdrCcPackInto(const HttpHdrCc * cc, Packer * p)
  {
      http_hdr_cc_type flag;
      int pcount = 0;
--- 198,212 ----
***************
*** 273,288 ****
  	    /* handle options with values */
  	    if (flag == CC_MAX_AGE)
  		packerPrintf(p, "=%d", (int) cc->max_age);
  
  	    if (flag == CC_S_MAXAGE)
  		packerPrintf(p, "=%d", (int) cc->s_maxage);
! 		// miaohong add
! 	    if (flag == CC_C_MAXAGE)
! 		packerPrintf(p, "=%d", (int) cc->c_maxage);
! 		
  	    if (flag == CC_MAX_STALE && cc->max_stale >= 0)
  		packerPrintf(p, "=%d", (int) cc->max_stale);
  
  	    if (flag == CC_STALE_WHILE_REVALIDATE)
  		packerPrintf(p, "=%d", (int) cc->stale_while_revalidate);
  
--- 220,232 ----
  	    /* handle options with values */
  	    if (flag == CC_MAX_AGE)
  		packerPrintf(p, "=%d", (int) cc->max_age);
  
  	    if (flag == CC_S_MAXAGE)
  		packerPrintf(p, "=%d", (int) cc->s_maxage);
! 
  	    if (flag == CC_MAX_STALE && cc->max_stale >= 0)
  		packerPrintf(p, "=%d", (int) cc->max_stale);
  
  	    if (flag == CC_STALE_WHILE_REVALIDATE)
  		packerPrintf(p, "=%d", (int) cc->stale_while_revalidate);
  
***************
*** 298,312 ****
  {
      assert(cc && new_cc);
      if (cc->max_age < 0)
  	cc->max_age = new_cc->max_age;
      if (cc->s_maxage < 0)
  	cc->s_maxage = new_cc->s_maxage;
- 	// miaohong add
- 	if (cc->c_maxage < 0)
- 	cc->c_maxage = new_cc->c_maxage;
      if (cc->max_stale < 0)
  	cc->max_stale = new_cc->max_stale;
      cc->mask |= new_cc->mask;
  }
  
  /* negative max_age will clean old max_Age setting */
--- 242,253 ----
***************
*** 330,356 ****
      if (s_maxage >= 0)
  	EBIT_SET(cc->mask, CC_S_MAXAGE);
      else
  	EBIT_CLR(cc->mask, CC_S_MAXAGE);
  }
  
- //miaohong add
- 
- /* negative s_maxage will clean old s-maxage setting */
- void
- httpHdrCcSetCMaxAge(HttpHdrCc * cc, int c_maxage)
- {
-     assert(cc);
-     cc->c_maxage = c_maxage;
-     if (c_maxage >= 0)
- 	EBIT_SET(cc->mask, CC_C_MAXAGE);
-     else
- 	EBIT_CLR(cc->mask, CC_C_MAXAGE);
- }
- 
- 
  void
  httpHdrCcUpdateStats(const HttpHdrCc * cc, StatHist * hist)
  {
      http_hdr_cc_type c;
      assert(cc);
      for (c = 0; c < CC_ENUM_END; c++)
--- 271,282 ----
*** src\HttpHeader.c 2013-12-02 14:28:20.000000000 +-0800
--- src\HttpHeader.c 2008-09-25 10:33:37.000000000 +-0800
***************
*** 564,577 ****
  		("WARNING: found whitespace in HTTP header name {%s}\n", getStringPrefix(field_start, field_end));
  	    if (!Config.onoff.relaxed_header_parser) {
  		httpHeaderEntryDestroy(e);
  		return httpHeaderReset(hdr);
  	    }
  	}
- 	// add miaohong
- 	//printf("[Debug for suning] header info :  %s = %s \n",e->name.buf,e->value.buf);
  	httpHeaderAddEntry(hdr, e);
      }
      return 1;			/* even if no fields where found, it is a valid header */
  }
  
  /* packs all the entries using supplied packer */
--- 564,575 ----
***************
*** 965,998 ****
  httpHeaderPutAuth(HttpHeader * hdr, const char *auth_scheme, const char *realm)
  {
      assert(hdr && auth_scheme && realm);
      httpHeaderPutStrf(hdr, HDR_WWW_AUTHENTICATE, "%s realm=\"%s\"", auth_scheme, realm);
  }
  
- //miaohong add
  void
- m_httpHeaderPutCc(HttpHeader * hdr, const HttpHdrCc * cc)
- {
-     MemBuf mb;
-     Packer p;
-     assert(hdr && cc);
-     /* remove old directives if any */
-     httpHeaderDelById(hdr, HDR_CACHE_CONTROL);
-     /* pack into mb */
-     memBufDefInit(&mb);
-     packerToMemInit(&p, &mb);
-     m_httpHdrCcPackInto(cc, &p);
-     /* put */
-     httpHeaderAddEntry(hdr, httpHeaderEntryCreate(HDR_CACHE_CONTROL, NULL, mb.buf));
-     /* cleanup */
-     packerClean(&p);
-     memBufClean(&mb);
- }
- 
- 
- void
  httpHeaderPutCc(HttpHeader * hdr, const HttpHdrCc * cc)
  {
      MemBuf mb;
      Packer p;
      assert(hdr && cc);
      /* remove old directives if any */
--- 963,975 ----
*** src\protos.h 2013-11-29 16:17:49.000000000 +-0800
--- src\protos.h 2010-03-08 00:00:07.000000000 +-0800
***************
*** 371,384 ****
  extern void httpHdrCcDestroy(HttpHdrCc * cc);
  extern HttpHdrCc *httpHdrCcDup(const HttpHdrCc * cc);
  extern void httpHdrCcPackInto(const HttpHdrCc * cc, Packer * p);
  extern void httpHdrCcJoinWith(HttpHdrCc * cc, const HttpHdrCc * new_cc);
  extern void httpHdrCcSetMaxAge(HttpHdrCc * cc, int max_age);
  extern void httpHdrCcSetSMaxAge(HttpHdrCc * cc, int s_maxage);
- //miaohong add
- extern void httpHdrCcSetCMaxAge(HttpHdrCc * cc, int s_maxage);
  extern void httpHdrCcUpdateStats(const HttpHdrCc * cc, StatHist * hist);
  extern void httpHdrCcStatDumper(StoreEntry * sentry, int idx, double val, double size, int count);
  
  /* Http Range Header Field */
  extern HttpHdrRange *httpHdrRangeParseCreate(const String * range_spec);
  /* returns true if ranges are valid; inits HttpHdrRange */
--- 371,382 ----
*** src\structs.h 2013-11-29 16:14:56.000000000 +-0800
--- src\structs.h 2008-09-25 10:33:37.000000000 +-0800
***************
*** 1014,1027 ****
  };
  
  /* http cache control header field */
  struct _HttpHdrCc {
      int mask;
      int max_age;
- 	//miaohong add
- 	int c_maxage;
      int s_maxage;
      int max_stale;
      int stale_while_revalidate;
      int stale_if_error;
      String other;
  };
--- 1014,1025 ----


{% endhighlight %}


