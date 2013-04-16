.EQ
.EN
.PS

down
Ngx_pool_t: [
Last:box "*last" shaded "lightgray" height 0.2
End:box "*end" shaded "lightgray" height 0.2
Next:box "*next" shaded "lightgray" height 0.2
Failed:box "failed" shaded "lightgray" height 0.2
Max:box "max" shaded "lightblue" height 0.2
Current:box "*current" shaded "lightblue" height 0.2
Chain:box "*chain" shaded "lightblue" height 0.2
Large:box "*large" shaded "lightblue" height 0.2
Cleanup:box "* cleanup" shaded "lightblue" height 0.2
Log:box "*log" shaded "lightblue" height 0.2
Used:box "used" shaded "blue" height 0.8
Data:box "data" height 0.2
]
arc from Ngx_pool_t.End.w to Ngx_pool_t.Data.sw ->

line dashed from Ngx_pool_t.Last.ne right 0.75

line dashed from Ngx_pool_t.Failed.se right 0.75

move to Ngx_pool_t.End.se right "ngx_pool_data_t"

spline left 0.5 then up 1 then right 0.4 from Ngx_pool_t.Current.w to Ngx_pool_t.Last.nw ->

spline left 0.25 then down 2.7 then right 0.24 from Ngx_pool_t.Last.w to Ngx_pool_t.Used.sw ->

up
move 1.5 
right
move 2.5
down

Ngx_pool_data_t1: [
Last:box "*last" shaded "lightgray" height 0.2
End:box "*end" shaded "lightgray" height 0.2
Next:box "*next" shaded "lightgray" height 0.2
Failed:box "failed" shaded "lightgray" height 0.2
Used:box "used" shaded "blue" height 0.8
Data:box "data" height 0.2
]

spline right 0.25 then down 0.75 from Ngx_pool_t.Next.e to Ngx_pool_data_t1.Last.nw ->
spline left 0.25 then down 1.5 then right 0.24 from Ngx_pool_data_t1.Last.w to Ngx_pool_data_t1.Used.sw ->

up
move 1.6
right
move 1.5
down
Ngx_pool_data_t2: [
Last:box "*last" shaded "lightgray" height 0.2
End:box "*end" shaded "lightgray" height 0.2
Next:box "*next" shaded "lightgray" height 0.2
Failed:box "failed" shaded "lightgray" height 0.2
Used:box "used" shaded "blue" height 0.2
Data:box "data" height 0.8
]

spline right 0.25 then up 0.25 from Ngx_pool_data_t1.Next.e to Ngx_pool_data_t2.Last.nw ->
spline right 0.25 then down 0.7 from Ngx_pool_data_t2.Last.e to Ngx_pool_data_t2.Used.se ->

move to Ngx_pool_t.Data.e right

right
move 0.2
up
move 1.5
down
Ngx_pool_large_s1:[
Next:box "next" shaded "lightyellow" height 0.2
Data:box "alloc" shaded "yellow" height 0.8
]

spline from Ngx_pool_t.Large.e to Ngx_pool_large_s1.Next.nw ->

.PE 
