---
layout: post
title: nginx module : Hello world
---

###ningx从写模块开始:
{% highlight bash%}
#config
ngx_addon_name=ngx_http_mytest_module
HTTP_MODULES="$HTTP_MODULES ngx_http_mytest_module"
NGX_ADDON_SRCS="$NGX_ADDON_SRCS $ngx_addon_dir/ngx_http_mytest_module.c"
{% endhighlight %}

{% highlight c %}
//ngx_http_mytest_module.c

#include <fcntl.h>

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


static char* ngx_http_mytest(ngx_conf_t *cf,ngx_command_t* cmd,void *conf);
static void* ngx_http_mytest_create_loc_conf(ngx_conf_t*cf);
static char* ngx_http_mytest_meger_loc_conf(ngx_conf_t*cf,void*parent,void*child);
static ngx_int_t ngx_http_mytest_handler(ngx_http_request_t *r);

typedef struct {
    ngx_str_t myteststr;
}ngx_http_mytest_loc_conf_t;

static ngx_command_t ngx_http_mytest_commands[]={
    { ngx_string("mytest"),
      NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_mytest,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_mytest_loc_conf_t,myteststr),
      NULL },
    ngx_null_command
};

static ngx_http_module_t ngx_http_mytest_module_ctx = {
    NULL, /* preconfiguration */
    NULL, /* postconfiguration */

    NULL, /* create main configuration */
    NULL, /* init main configuration */

    NULL, /* create server configuration */
    NULL, /* merge server configuration */

    ngx_http_mytest_create_loc_conf, /* create location configuration */
    ngx_http_mytest_meger_loc_conf /* merge location configuration */
};

ngx_module_t ngx_http_mytest_module = {
    NGX_MODULE_V1,
    &ngx_http_mytest_module_ctx,
    ngx_http_mytest_commands,
    NGX_HTTP_MODULE,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NGX_MODULE_V1_PADDING
};

static ngx_int_t ngx_http_mytest_handler(ngx_http_request_t *r)
{
    char* handler_name = "ngx_http_mytest_handler\n";
    
    ngx_int_t rc;
    ngx_buf_t *b;
    ngx_chain_t out;
    ngx_http_mytest_loc_conf_t *mytest_conf;

    mytest_conf = ngx_http_get_module_loc_conf(r,ngx_http_mytest_module);
    
    if (!(r->method & (NGX_HTTP_GET))) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    rc = ngx_http_discard_request_body(r);

    if (rc) {
        return rc;
    }

    r->headers_out.content_type.len = sizeof("text/html")-1;
    r->headers_out.content_type.data = (u_char*) "text/html";

    b = ngx_pcalloc(r->pool,sizeof(ngx_buf_t));
    if (b==NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    out.buf = b;
    out.next = NULL;

    b->pos = mytest_conf->myteststr.data;
    b->last = mytest_conf->myteststr.data + mytest_conf->myteststr.len;

    b->memory = 1;
    b->last_buf = 1;

    r->headers_out.status = NGX_HTTP_OK;
    r->headers_out.content_length_n = mytest_conf->myteststr.len;

    rc = ngx_http_send_header(r);

    if (rc==NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }
    

    return ngx_http_output_filter(r,&out);
    
}

static char* ngx_http_mytest(ngx_conf_t* cf,ngx_command_t* cmd,void* conf)
{
    ngx_http_core_loc_conf_t *clcf;

    clcf = ngx_http_conf_get_module_loc_conf(cf,ngx_http_core_module);
    clcf->handler = ngx_http_mytest_handler;

    ngx_conf_set_str_slot(cf,cmd,conf);

    return NGX_CONF_OK;
}

static void* ngx_http_mytest_create_loc_conf(ngx_conf_t* cf)
{
    ngx_http_mytest_loc_conf_t *mytest_conf;
    mytest_conf = ngx_pcalloc(cf->pool,sizeof(ngx_http_mytest_loc_conf_t));
    if (!mytest_conf) {
        return NGX_CONF_ERROR;
    }
    mytest_conf->myteststr.len = 0;
    mytest_conf->myteststr.data = NULL;
    return mytest_conf;
}

static char* ngx_http_mytest_meger_loc_conf(ngx_conf_t*cf,void* parent,void* child)
{
    ngx_http_mytest_loc_conf_t *prev = parent;
    ngx_http_mytest_loc_conf_t *mytest_conf = child;
    ngx_conf_merge_str_value(mytest_conf->myteststr,prev->myteststr,"");
    return NGX_CONF_OK;
}

{% endhighlight %}

一个hello world级别的模块，add-module之后nginx会把这些代码一起编译到整个应用里。但是对于一个初学的开发者就开始迷糊了，这些代码是如何被编译，如何被调用的呢?

下面就带着这个问题一起一步一步分析一下，这篇文章也是随着我自己的分析一点一点往下写的，一个肯定的结论也是由许多很2的猜想里逐渐排除出来的。所以有些分析和理解不到位的地方，随着深入应该会更加明确，文章尽可能保存我自己的思路，以便整理，也好留给和我一样的初学者一个可以寻觅的线索。并且一边记录一边分析也给自己提供了一个更加理性思考的条件，去回答自己提出的问题，往往不记录，不输出的情况比较容易以表面现象盲下定论，这也是我之前在学校一直在犯的错误，人太懒了又太急功近利。

我一直认为思路比结论要重要，大神们经常给出一个"这样做就对的"结论，但是从曾经的"我认为这样没错啊"到大神的"对"往往有千转百折也绕不过的弯,并且大神们羞涩于写些自己认为应该是众所周知的技巧,这又在一定程度上提高了入行的门槛，这里尽可能补充一些大神们漏掉的并且我又恰好知道的。:)


**言归正传:**

###configure

归根溯源，一切都从configure开始。以文本打开configure，"Copyright (C) Igor Sysoev" -_-!!

我们只关心关于add-module的选项,--add-module参数在auto/option中256行赋值了NGX_ADDONS变量。在auto/modules文件中有这么一段:
{% highlight bash %}
#auto/modules

if test -n "$NGX_ADDONS"; then

    echo configuring additional modules

    for ngx_addon_dir in $NGX_ADDONS
    do
        echo "adding module in $ngx_addon_dir"

        if test -f $ngx_addon_dir/config; then
            . $ngx_addon_dir/config

            echo " + $ngx_addon_name was configured"

        else
            echo "$0: error: no $ngx_addon_dir/config was found"
            exit 1
        fi
    done
fi
{% endhighlight %}

这里已经可以看出来模块开发的时候为什么会需要一个config文件了，它是属于configure的一部分,并且也解答了NGX_ADDON_SRCS,ngx_addon_name,HTTP_MODULES这些变量从何而来。

{% highlight bash %}
if test -n "$NGX_ADDON_SRCS"; then

    ngx_cc="\$(CC) $ngx_compile_opt \$(CFLAGS) $ngx_use_pch \$(ALL_INCS)"

    for ngx_src in $NGX_ADDON_SRCS
    do
        ngx_obj="addon/`basename \`dirname $ngx_src\``"

        ngx_obj=`echo $ngx_obj/\`basename $ngx_src\` \
            | sed -e "s/\//$ngx_regex_dirsep/g"`

        ngx_obj=`echo $ngx_obj \
            | sed -e "s#^\(.*\.\)cpp\\$#$ngx_objs_dir\1$ngx_objext#g" \
                  -e "s#^\(.*\.\)cc\\$#$ngx_objs_dir\1$ngx_objext#g" \
                  -e "s#^\(.*\.\)c\\$#$ngx_objs_dir\1$ngx_objext#g" \
                  -e "s#^\(.*\.\)S\\$#$ngx_objs_dir\1$ngx_objext#g"`

        ngx_src=`echo $ngx_src | sed -e "s/\//$ngx_regex_dirsep/g"`

        cat << END                                            >> $NGX_MAKEFILE

$ngx_obj:       \$(ADDON_DEPS)$ngx_cont$ngx_src
        $ngx_cc$ngx_tab$ngx_objout$ngx_obj$ngx_tab$ngx_src$NGX_AUX

END
     done

fi
{% endhighlight %}

在auto/make脚本中有以上代码片段,并在configure中被调用,用来把模块目录中的config里涉及的源文件添加到生成的Makefile中.这样编译的时候就会被连带这nginx的基础框架一起编译进去了.

###nginx启动过程中的模块加载

在objs目录下为configure后生成的一些源文件,里面有些宏定义,以及包含所有模块的数组.这个数组在ngx_modules.c文件中.所有的模块加载,初始化也都是围绕这个数组来进行操作的.

第一次对ngx_modules进行初始化是在core/nginx.c文件main函数中:
{% highlight c %}
//core/nginx.c:main

ngx_max_module = 0;
for (i = 0; ngx_modules[i]; i++) {
    ngx_modules[i]->index = ngx_max_module++;
}
{% endhighlight %}
对ngx_modules每个模块进行编号.

随后在core/ngx_cycle.c的init_cycle函数中:
{% highlight c %}
//core/ngx_cycle.c:ngx_init_cycle

for (i = 0; ngx_modules[i]; i++) {
    if (ngx_modules[i]->type != NGX_CORE_MODULE) {
        continue;
    }

    module = ngx_modules[i]->ctx;

    if (module->create_conf) {
        rv = module->create_conf(cycle);
        if (rv == NULL) {
            ngx_destroy_pool(pool);
            return NULL;
        }
        cycle->conf_ctx[ngx_modules[i]->index] = rv;
    }
}
{% endhighlight %}
这里只对nginx的核心级模块ngx_core_module进行调用create_conf()函数的调用. 而create_conf函数的返回值类型是void*,我们可以参考"void* ngx_core_module_create_conf(ngx_cycle_t *cycle)"这个函数,其返回的值类型为"ngx_core_conf_t*",即一个关乎自己模块的自定义的存放配置的结构体,通过create_conf对其进行一些内存分配和初始化的操作.从这里也可以看出来nginx模块设计的一些端倪.

核心级的模块都有:ngx_core_module,ngx_http_module,ngx_openssl_module,ngx_events_module,ngx_errlog_module,ngx_google_perftools_module.

这里执行create_conf的模块有: ngx_core_module,ngx_openssl_module,ngx_google_perftools_module.

init_cycle中随后又调用了ngx_conf_parse函数,解析指定的配置文件, 并调用ngx_conf_handler去执行cmd->set的回调函数,对比上边的源码也就是"ngx_command_t ngx_http_mytest_commands"结构体中的"char*ngx_http_mytest"函数.

这里ngx_conf_parse函数也是相当重要的一个阶段,对各个模块通过解析配置文件进行设置.下面在进行详细的介绍. 

随后还是init_cycle函数中:

{% highlight c %}
//ngx_cycle.c:ngx_init_cycle

for (i = 0; ngx_modules[i]; i++) {
    if (ngx_modules[i]->type != NGX_CORE_MODULE) {
       continue;
    }

    module = ngx_modules[i]->ctx;

    if (module->init_conf) {
        if (module->init_conf(cycle, cycle->conf_ctx[ngx_modules[i]->index])
            == NGX_CONF_ERROR)
        {
            environ = senv;
            ngx_destroy_cycle_pools(&conf);
            return NULL;
        }
    }
}
{% endhighlight %}

之后再调用各个核心级模块的ctx->init_conf函数和module->init_module函数.

{% highlight c %}
//ngx_cycle.c:ngx_init_cycle

for (i = 0; ngx_modules[i]; i++) {
    if (ngx_modules[i]->init_module) {
        if (ngx_modules[i]->init_module(cycle) != NGX_OK) {
            /* fatal */
            exit(1);
        }
    }
}
{% endhighlight %}

之上是各个模块在初始化的时候执行的一些函数.下面看下针对于每个要启动的worker进程的一些模块加载.

在ngx_processes_cycle.c:ngx_worker_process_init()函数中:

{% highlight c %} 
//ngx_processes_cycle.c:ngx_worker_process_init

for (i = 0; ngx_modules[i]; i++) {
    if (ngx_modules[i]->init_process) {
        if (ngx_modules[i]->init_process(cycle) == NGX_ERROR) {
            /* fatal */
            exit(2);
        }
    }
}
{% endhighlight %}
调用每个模块的ngx_modules->init_process函数

以及在进程退出的时候执行exit_process函数和exit_master函数

{% highlight c %} 
//ngx_process_cycle.c:ngx_worker_process_exit

for (i = 0; ngx_modules[i]; i++) {
    if (ngx_modules[i]->exit_process) {
        ngx_modules[i]->exit_process(cycle);
    }
}

{% endhighlight %} 

{% highlight c %} 
//ngx_process_cycle.c:ngx_master_process_exit

for (i = 0; ngx_modules[i]; i++) {
    if (ngx_modules[i]->exit_master) {
        ngx_modules[i]->exit_master(cycle);
    }
}
{% endhighlight %}

在以上的启动过程中并未看到http module和event module的各个子模块的加载,这是因为这些子模块是单独由各个核心模块自己负责的.下面我们再深入的跟踪一下各个子模块是如何被加载的.特别是http module.



###tobe continued...

coding...

#back:


每个core模块大致的加载流程也就是入上文所描述的.但是作为开发,往往是开发core模块下的一些子模块.这些子模块的各种配置与执行过程又由core模块分别负责.这也是nginx在设计上的一个亮点.并且相当的亮.

在ngx_init_cycle中从配置文件的解析开始,下面这段代码已经将所有的配置文件解析完毕了. 

{% highlight c %}
/* core/ngx_cycle.c:ngx_init_cycle */

if (ngx_conf_parse(&conf, &cycle->conf_file) != NGX_CONF_OK) {
    environ = senv;
    ngx_destroy_cycle_pools(&conf);
    return NULL;
}

{% endhighlight %}


实事上在ngx_conf_parse中调用了ngx_command_t的回调函数,在一些核心模块中往往都是通过这些回调函数再去执行ngx_conf_parse再结合自己的模块结构来解析自己的模块的相关配置的.这里就是诞生了ngx_http_module_t.这个是http core module再次向外提供模块式接口的一个统一数据结构.对于初次做nginx开发时,会认为这些是理所当然的,nginx就是这么提供的.而再去深入一下实现也就会发现这些是由各个core模块独立管理的.并非nginx统筹管理的.绕清楚了这一点,就会觉察到作为开发者也是可以通过nginx的这个机制来为其他开发者来开发基础模块的.

回到http module.在src/http/ngx_http.c文件中, 可以看到:

{% highlight c %}

static ngx_command_t  ngx_http_commands[] = {

    { ngx_string("http"),
      NGX_MAIN_CONF|NGX_CONF_BLOCK|NGX_CONF_NOARGS,
      ngx_http_block,
      0,
      0,
      NULL },

      ngx_null_command
};

{% endhighlight %}

对于http core模块来讲,它单纯到只有一条配置指令, 该指令的回调函数是ngx_http_block.它同样是会在ngx_conf_parse时被执行到的.也可以看到它的性质是NGX_CONF_BLOCK-这是一个精妙的地方.它是不支持参数的,并且是个大括号.这也就说明了由它来负责"http"指令后面那一个大括号里面的内容.这点也可以在ngx_http_block中得到证明.大段的代码这里就不贴了,也就是在ngx_http_block中又通过ngx_conf_parse解析了http大括号中的内容,同时调用ngx_http_module_t的各个回调函数来创建配置结构体,初始化结构体以及等等的.这里的一切都是http模块的世界.将ngx_http_block这段代码看完基本上问题也都得到了解答了.

最需要强调的一点就是ngx_http_module_t和ngx_http_module不是一个东西.最初草草看代码时心中有太多的疑惑.实事上看下event模块的加载或许更加简捷清楚一些.毕竟http模块有些许复杂.


