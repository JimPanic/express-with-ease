path = require 'path'

module.exports =
	port: 4000
	base_path: '/'
	base_resource: 'sessions'
	resources_path: 'resources'
	view_engine: 'jade'
	views_path:  'views'
	assets_path: 'public'

	# Comment out the whole SSL block if you want to disable it.
	ssl:
		key:  path.join('config', 'server.key')
		cert: path.join('config', 'server.crt')
