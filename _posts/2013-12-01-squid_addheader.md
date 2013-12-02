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



{% endhighlight %}


