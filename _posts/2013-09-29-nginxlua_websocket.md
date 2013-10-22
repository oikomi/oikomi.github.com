---
layout: post
title: 利用openresty搭建基于websocket的聊天室
---

利用openresty搭建基于websocket的聊天室
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2013/09/29/nginxlua_websocket.html




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

