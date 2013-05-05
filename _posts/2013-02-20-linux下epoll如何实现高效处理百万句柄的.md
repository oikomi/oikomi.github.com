## linux下epoll如何实现高效处理百万句柄的 ##

**epoll** 是 linux 平台上一种*IO多路复用技术*，可以非常高效的处理数以百万计的socket句柄，比起以前的select和poll效率高大发了。我们用起epoll来都感觉挺爽，确实快，那么，它到底为什么可以高速处理这么多并发连接呢？

### 先简单回顾下如何使用C库封装的3个epoll系统调用吧 ###

{% highlight c %}
int epoll_create(int size);
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);  
int epoll_wait(int epfd, struct epoll_event *events,int maxevents, int timeout); 
{% endhighlight %}