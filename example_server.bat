@echo off
title NET Online Dedicated Manager - Jupiter
COLOR 3

:load
echo SERVER START - OK [%time%]
start /wait /affinity 0xC dedicated\xrEngine.exe -i -save_loot -silent_error_mode -fsltx ..\fsgame_s.ltx -start server(jupiter_stnet_v2/ow/hname=jup_stalkernet_i9_9900k/public=0/portsv=5446/portgs=5445/vote=8/maxplayers=30/spectrmds=15) client(localhost/portcl=5447)

goto load
