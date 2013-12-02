---
layout: post
title: Squid定制开发(三)之添加修改header头
---

Squid定制开发(三)之添加修改header头
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2013/12/01/squid_addheader.html


最近有个需求，需要：



{% highlight java %}

左侧基准文件夹：D:\vpc\shared\suning\squid-suning
右侧基准文件夹：D:\vpc\shared\suning\squid-2.7.STABLE9

文件：src\client_side.c
1779,1781d1778
< 	//miaohong add	
< 	m_httpHeaderPutCc(hdr, http->request->cache_control);
< 	
1970,1975d1966
< 	//miaohong add
< 	//if(httpHeaderHas(hdr,HDR_CACHE_CONTROL))
< 	//{
< 		//printf("HDR_CACHE_CONTROL exist \n");
< 	//}
< 	//printf("httpHeaderGetCc : %d---\n",httpHeaderGetCc(hdr)->c_maxage);
2764,2765d2754
< 	//miaohong add
< 	//printf("cc cmax: %d-----------\n",http->request->cache_control->c_maxage);
3491,3492d3479
< 
< 
3496,3497d3482
< 	//miaohong add
< 	//printf("-----in clientProcessRequest---\n");
3942,3943d3926
< 	//add miaohong
< 	//printf("------in clientTryParseRequest----\n");
4155d4137
< 	//printf("--------in clientReadRequest-------\n");

文件：src\enums.h
282,283d281
<     //miaohong add
<     CC_C_MAXAGE,

文件：src\HttpHdrCc.c
51,52d50
<     //miaohong add
<     {"c-maxage", CC_C_MAXAGE},
85,86c83
< 	// miaohong modify
<     cc->max_age = cc->s_maxage = cc->c_maxage = cc->max_stale = cc->stale_if_error - 1;
---
>     cc->max_age = cc->s_maxage = cc->max_stale = cc->stale_if_error - 1;
152,160d148
< 	//miaohong add
< 	case CC_C_MAXAGE:
< 	    if (!p || !httpHeaderParseInt(p, &cc->c_maxage)) {
< 		debug(65, 2) ("httpHdrCcParseInit: invalid c-maxage specs near '%s'\n", item);
< 		cc->c_maxage = -1;
< 		EBIT_CLR(cc->mask, type);
< 	    }
< 	    break;
< 		
216,217d203
< 	//miaohong modify
< 	dup->c_maxage = cc->c_maxage;
221,259d206
< 
< //miaohong add
< 
< void
< m_httpHdrCcPackInto(const HttpHdrCc * cc, Packer * p)
< {
<     http_hdr_cc_type flag;
<     int pcount = 0;
<     assert(cc && p);
<     for (flag = 0; flag < CC_ENUM_END; flag++) {
< 	if (EBIT_TEST(cc->mask, flag) && flag != CC_OTHER && flag != CC_C_MAXAGE) {
< 
< 	    /* print option name */
< 	    packerPrintf(p, (pcount ? ", %s" : "%s"), strBuf(CcFieldsInfo[flag].name));
< 
< 	    /* handle options with values */
< 	    if (flag == CC_MAX_AGE)
< 		packerPrintf(p, "=%d", (int) cc->c_maxage);
< 
< 	    if (flag == CC_S_MAXAGE)
< 		packerPrintf(p, "=%d", (int) cc->s_maxage);
< 		// miaohong add
< 	    //if (flag == CC_C_MAXAGE)
< 		//packerPrintf(p, "=%d", (int) cc->c_maxage);
< 		
< 	    if (flag == CC_MAX_STALE && cc->max_stale >= 0)
< 		packerPrintf(p, "=%d", (int) cc->max_stale);
< 
< 	    if (flag == CC_STALE_WHILE_REVALIDATE)
< 		packerPrintf(p, "=%d", (int) cc->stale_while_revalidate);
< 
< 	    pcount++;
< 	}
<     }
<     if (strLen(cc->other))
< 	packerPrintf(p, (pcount ? ", %s" : "%s"), strBuf(cc->other));
< }
< 
< 
279,282c226
< 		// miaohong add
< 	    if (flag == CC_C_MAXAGE)
< 		packerPrintf(p, "=%d", (int) cc->c_maxage);
< 		
---
> 
304,306d247
< 	// miaohong add
< 	if (cc->c_maxage < 0)
< 	cc->c_maxage = new_cc->c_maxage;
336,350d276
< //miaohong add
< 
< /* negative s_maxage will clean old s-maxage setting */
< void
< httpHdrCcSetCMaxAge(HttpHdrCc * cc, int c_maxage)
< {
<     assert(cc);
<     cc->c_maxage = c_maxage;
<     if (c_maxage >= 0)
< 	EBIT_SET(cc->mask, CC_C_MAXAGE);
<     else
< 	EBIT_CLR(cc->mask, CC_C_MAXAGE);
< }
< 
< 

文件：src\HttpHeader.c
570,571d569
< 	// add miaohong
< 	//printf("[Debug for suning] header info :  %s = %s \n",e->name.buf,e->value.buf);
971d968
< //miaohong add
973,992d969
< m_httpHeaderPutCc(HttpHeader * hdr, const HttpHdrCc * cc)
< {
<     MemBuf mb;
<     Packer p;
<     assert(hdr && cc);
<     /* remove old directives if any */
<     httpHeaderDelById(hdr, HDR_CACHE_CONTROL);
<     /* pack into mb */
<     memBufDefInit(&mb);
<     packerToMemInit(&p, &mb);
<     m_httpHdrCcPackInto(cc, &p);
<     /* put */
<     httpHeaderAddEntry(hdr, httpHeaderEntryCreate(HDR_CACHE_CONTROL, NULL, mb.buf));
<     /* cleanup */
<     packerClean(&p);
<     memBufClean(&mb);
< }
< 
< 
< void

文件：src\protos.h
377,378d376
< //miaohong add
< extern void httpHdrCcSetCMaxAge(HttpHdrCc * cc, int s_maxage);

文件：src\structs.h
1020,1021d1019
< 	//miaohong add
< 	int c_maxage;


{% endhighlight %}


