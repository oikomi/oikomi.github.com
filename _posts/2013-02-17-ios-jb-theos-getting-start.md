---
layout: post
title: Theos/Getting Started(翻译)
---

原文链接:[http://iphonedevwiki.net/index.php/Theos/Getting_Started](http://iphonedevwiki.net/index.php/Theos/Getting_Started)

# Theos入门

## 目标

这章包含了[Theos](http://iphonedevwiki.net/index.php/Theos)的安装和用其创建一个新的项目。

## 要求

- 一个基于unix的操作系统(Mac OS X, iOS (jailbroken))，或者多数的Linux发行版本

- subversion 或者 git

- curl

- perl

- dpkg

- xcode安装的官方工具链和SDK

- 终端

- Objective-C 相关知识

## 安装依赖

### 针对Mac OS X

Mac OS X 默认安装了svn, curl和perl, 但你你仍然需要安装SDK和编译工具链。最简单的方法就是从官方网站获取[iOS SDK](http://developer.apple.com/iphone/) (你必须先注册一个开发者帐号才能下载)。

### 针对iOS

安装SDK

### 针对Linux

后续补充

## 安装Theos

1. 打开终端

2. 选择一个你安装Theos的位置，如果你不能确定，/opt/theos是一个不错的选择

	`export THEOS=/opt/theos`

	如果你选择了一个不在你的home目录内的地方，那么你可以需要root权限去执行命令。

3. 下载最新版本的Theos:
   - 使用git:`git clone git://github.com/DHowett/theos.git $THEOS`
   - 或者使用svn:`svn co http://svn.howett.net/svn/theos/trunk $THEOS`


   译者注:
   这里的git源不是很好用，我用的是:`git://github.com/rpetrich/theos.git`
   clone后执行`git submodule update --init`拉取相关头文件

4. 下载ldid到$THEOS/bin:

	`curl -s http://dl.dropbox.com/u/85683265/ldid > $THEOS/bin/ldid; chmod +x $THEOS/bin/ldid`

或者使用下面方法确保其版本是最新的

{% highlight bash %}
git clone git://git.saurik.com/ldid.git
cd ldid
git submodule update --init
./make.sh
cp -f ./ldid $THEOS/bin/ldid
{% endhighlight %}

译者注:

最好使用下面的方法，因为dropbox被墙了...


## 在iOS设备上安装theos

1. 在`/etc/apt/sources.list.d/coredev.nl.list`路径下创建文件，包含下面的内容:

	`deb http://coredev.nl/cydia iphone main`

2. 在`/etc/apt/sources.list.d/howett.net.list`路径下创建文件，包含下面内容:

	`deb http://nix.howett.net/theos ./`

3. 确保APT0.6已经安装，在root权限下终端里执行下面命令:

	`apt-get update`

	`apt-get install perl net.howett.theos`

	注:Theos将被安装到`/var/theos/`，后面文章中将使用`$THEOS`代替描述。

## 创建项目

通过使用NIC(New Instance Creator)，Theos可以帮助你创建一个新项目的模板，执行这个命令不需要root权限：

`$THEOS/bin/nic.pl`

NIC在创建项目前将会提示你输入必要的信息。

## NIC例子

当你使用nic去创建项目时，你可以得到如下输出:


{% highlight bash %}
$ $THEOS/bin/nic.pl
NIC 1.0 - New Instance Creator
------------------------------
  [1.] iphone/application
  [2.] iphone/library
  [3.] iphone/preference_bundle
  [4.] iphone/tool
  [5.] iphone/tweak
Choose a Template (required): 1
Project Name (required): iPhoneDevWiki
Package Name [com.yourcompany.iphonedevwiki]: net.howett.iphonedevwiki
Authour/Maintainer Name [Dustin L. Howett]:              
Instantiating iphone/application in iphonedevwiki/...
Done.
$
{% endhighlight %}

上面的指令将会在你的当前目录创建一个名为`./iphonedevwiki`文件夹(确保你有创建文件夹的权限)

## 开始

你可以从[http://uv.howett.net/ipf.html](http://uv.howett.net/ipf.html)这里了解到是怎么通过Makefile和Theos来进行工作。

## 帮助

如果你需要更多的帮助，或者你有其他关于Theos的问题，可以链接到#theos irc.saurik.com频道。


## 其他

这里[http://cl.ly/1u0l0U0y2I0T1g2s3D0O](http://cl.ly/1u0l0U0y2I0T1g2s3D0O)还有一个例子，跑一跑应该就知道jb是怎么回事儿了吧！

项目目录下执行:

`make`:编译项目

`make package`: 生成deb安装包

`make install`: 安装到手机

当然，安装到手机是需要提供手机联入wifi的ip的：`export THEOS_DEVICE_IP=192.1.1.1`

手机上也需要安装openssh

hava fun :)

EOF

