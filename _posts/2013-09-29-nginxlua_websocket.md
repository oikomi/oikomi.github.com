---
layout: post
title: 利用openresty搭建基于websocket的聊天室
---

利用openresty搭建基于websocket的聊天室
=====================

> **NOTE:** 原创文章，转载请注明：转载自 [blog.miaohong.org](http://blog.miaohong.org/) 本文链接地址: http://blog.miaohong.org/2013/09/29/nginxlua_websocket.html



{% highlight shell %}
#user  nobody;
worker_processes  1;
daemon off;
#error_log  logs/error.log;
error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;
    lua_shared_dict talks 1m;
    #gzip  on;

    server {
        listen       80;
        server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;
	location /s {
            content_by_lua_file /usr/local/openresty/nginx/conf/ws.lua; 
        }
	


	location /redis.html {
        content_by_lua_file /usr/local/openresty/nginx/conf/redis.lua;
    }
		
        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }

}
{% endhighlight %}


{% highlight lua %}

local count = 0
local server = require "resty.websocket.server"

--redis
local redis = require "resty.redis"
local red = redis:new()

red:set_timeout(1000) -- 1 sec

-- or connect to a unix domain socket file listened
-- by a redis server:
--     local ok, err = red:connect("unix:/path/to/redis.sock")

local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
	ngx.say("failed to connect: ", err)
	return
end

--redis

local wb, err = server:new {
  timeout = 500000,
  max_payload_len = 65535
}

if not wb then
  ngx.log(ngx.ERR, "failed to new websocket: ", err)
  return ngx.exit(444)
end

while true do
  local data, typ, err = wb:recv_frame()
  --local host = ngx.var.remote_addr
  local host = "s1"
  print(host)
  if wb.fatal then
	ngx.log(ngx.ERR, "failed to receive frame: ", err)
	return ngx.exit(444)
  end
  
  red:lpush(host,data)
  
  count = count + 1
  --for i=0, count-1,1 do
  local res, err = red:lrange(host, 0, -1)

  for i, res in pairs(res) do
	print(i)
	print(res)
	wb:send_text(host .. " says: " .. res)
	--ngx.say(res)
	-- process the scalar value
  end
  

  end
 -- if typ == "close" then  break  end
--[[
  if typ == "text" then
	local bytes, err = wb:send_text(data)
	if not bytes then
	  ngx.log(ngx.ERR, "failed to send text: ", err)
	  return ngx.exit(444)
	end
  end
]]

--wb:send_close()
{% endhighlight %}

