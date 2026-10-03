fx_version "cerulean"
game "gta5"
lua54 "yes"

name "jg-mech-ingame"
author "Wraith Development"
description "In-game UI to edit and save the JG Mechanic config"
version "1.0.0"

shared_scripts {
	"@ox_lib/init.lua",
	"config.lua",
}

client_scripts {
	"client/main.lua",
}

server_scripts {
	"@oxmysql/lib/MySQL.lua",
	"server/fs.js",
	"server/serialize.lua",
	"server/main.lua",
}

ui_page "web/dist/index.html"

files {
	"web/dist/index.html",
	"web/dist/assets/*",
	"web/dist/map/*",
}
