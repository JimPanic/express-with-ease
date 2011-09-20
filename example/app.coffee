path   = require 'path'

# Add current directory to `require`'s load paths.
require.paths.push __dirname

Server = require 'express-with-ease'

server = new Server require 'config'
server.listen()
