# Copyright (c) 2011 Brainsware
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

express = require 'express'
path    = require 'path'
fs      = require 'fs'
file    = require 'file'

# **Server** is an extensive wrapper for
# [`express.HTTPServer`](http://expressjs.com/guide.html#creating-a server).
#
# It takes care of setting important default values, as well as
# loading configuration, middleware and most importantly define
# **RESTful default routes**.
class Server
	constructor: (@config) ->
		@app = express.createServer @server_options()

		@configure()
		@register_middleware()
		@register_resources()

	# Sets values according to the config file.
	#
	# * `basepath`: `config.base_path`, defaults to `/`
	#
	# * `views`: `config.views_path`, defaults to `views/`
	#
	# * `view engine`: `config.view_engine`, defaults to `jade`
	#
	configure: ->
		@app.set 'basepath',    @config.base_path   or '/'
		@app.set 'views',       @config.views_path  or 'views'
		@app.set 'view engine', @config.view_engine or 'jade'

	# Registers middleware for development environment,
	# enabling output of exceptions incl. stack.
	development: =>
		@app.use express.errorHandler
			dumpExceptions: true
			showStack: true

		@app.use express.logger format: 'dev'

	# Registers necessary middleware.
	register_middleware: ->
		@app.use express.bodyParser()
		@app.use express.cookieParser()
		@app.use express.session { secret: @config.sessions.secret, store: @config.sessions.store }
		@app.use express.methodOverride()
		@app.use @app.router
		@app.use express.static @config.assets_path

		@app.configure 'development', @development

	# Fires up the server and starts listening on `config.port`
	listen: ->
		@app.listen(@config.port)

	# Checks whether SSL is enabled in the config and returns
	# necessary options for `express.createServer`.
	#
	# SSL is enabled by setting `config.ssl.key` and
	# `config.ssl.cert` to the respective (absolute, or relative
	# to the app root) paths.
	server_options: ->
		return {} unless @config.ssl?

		{
			key:  fs.readFileSync @config.ssl.key
			cert: fs.readFileSync @config.ssl.cert
		}

	# Find and register all available resources in `config.resources_path`
	register_resources: ->
		@controllers ||= []

		file.walkSync @config.resources_path, (start, directories, files) =>
			for filename in files when filename.match /\.coffee$/
				@register_controller(start, filename, @get_relative_path(start, filename))

	# Register routes for a specific resource controller
	register_controller: (start, filename, relative_path) ->
		route = @route_from_path(relative_path)

		@controllers[relative_path] = new require(path.join(start, filename))

		for method, fn of @controllers[relative_path].prototype
			@register_route method, route, @proxy.bind(@controllers[relative_path], fn, method, relative_path)

			# Additionally, the value of `config.base_resource` is used
			# to deduct what controller should map to `/`
			@register_route method, '/', @proxy.bind(@controllers[relative_path], fn, method, relative_path) if relative_path is @config.base_resource

	proxy: (fn, args...) ->
		fn(args[2...args.length]...)

	# Register a single route. This method uses `deduct_http_method`
	# and `deduct_route` to map accordingly.
	#
	#	*Note:* if you name a method other than `index`, `show`, `new`,
	#	`create`, `edit`, `update` or `destroy`, it will simply ignore it
	#	and assume this is a utility method.
	register_route: (method, route, fn) ->
		http_method = @deduct_http_method(method)
		@app[http_method] @deduct_route(method, route), fn if http_method?

	# Find out what HTTP method given method responds to
	#
	#	* `index`, `show`, `new`, `edit`: **GET**
	#
	#	* `create`: **POST**
	#
	#	* `update`: **PUT**
	#
	#	* `destroy`: **DELETE**
	#
	deduct_http_method: (method) ->
		switch method
			when 'index', 'show', 'new', 'edit' then 'get'
			when 'create'                       then 'post'
			when 'update'                       then 'put'
			when 'destroy'                      then 'delete'

	# Generates the relative path between the value of `config.resources_path`
	# and given resource (in this case identified by `start` and `filename`)
	get_relative_path: (start, filename) ->
		file.path.relativePath(@config.resources_path, path.join(start, path.basename(filename, '.coffee')))

	# Appends `:id`, `new` or `edit` to given route, according
	# to the method called.
	#
	#	* `index`, `create`: nothing is appended
	#
	#	* `show`, `update`, `destroy`: `:id` is appended
	#
	#	* `new`: `new` is appended
	#
	#	* `edit`: `edit` is appended
	deduct_route: (method, route) ->
		new_route = switch method
									when 'index', 'create'           then route
									when 'show', 'update', 'destroy' then path.join route, ':id'
									when 'new'                       then path.join route, 'new'
									when 'edit'                      then path.join route, ':id', 'edit'

		new_route + '.:format?'

	# Turns a relative path into an actual URI:
	#
	# * `/foo`: `/foo`
	#
	# * `/foo/bar`: `/foo/:foo_id/bar`
	#
	# * `/foo.namespace/bar`: `/foo/bar`
	#
	# *Note:* the :id part for the last resources in path
	# are appended later (`deduct_route`), according to the
	# available methods.
	route_from_path: (relative_path) ->
		route = '/'
		splitted_path = relative_path.split '/'

		for index, route_part of splitted_path
			# NOTE: index would be a string, splitted_path.length is a number.
			#       CoffeeScript automagically transforms `'=='` to `'==='`, which
			#       then fails as `'1' === 1` yields `false`.
			index = parseInt(index)

			route = if splitted_path.length == 1 or index == (splitted_path.length - 1)
				path.join route, route_part
			else if path.extname(route_part) is '.namespace'
				path.join route, path.basename(route_part, '.namespace')
			else
				path.join route, route_part, ":#{route_part}_id"

		route

module.exports = Server
