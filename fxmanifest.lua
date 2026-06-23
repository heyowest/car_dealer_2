fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'heyowest'
description 'Daily randomised NPC car dealership with a 3D showroom preview (QBox / ox)'
version '1.0.0'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
}

client_scripts {
    'client.lua',
    'showroom.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server_config.lua', -- server-only tuning (car pool, weights) — never sent to clients
    'server.lua',
}

ui_page 'ui/index.html'

files {
    'locales/*.json',
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'ox_target',
    'qbx_vehiclekeys',
    'oxmysql',
}
