EventEmitter = require('events').EventEmitter
Adapter      = require('hubot').adapter()
Robot        = require('hubot').robot()
net          = require 'net'

class Moo extends Adapter
    run: ->
        options =
            host: process.env.HUBOT_MOO_HOST
            port: parseInt process.env.HUBOT_MOO_PORT
            user: process.env.HUBOT_MOO_USER
            pass: process.env.HUBOT_MOO_PASS

        @bot = new MooClient options, @robot

        # Events to receive
        types = ['say', 'whisper', 'direct', 'help']

        types.forEach (type) =>
            if type is 'say'
                @bot.on type, (name, msg) =>
                    @robot.logger.debug "#{name} said: #{msg}"
                    user = @userForId name, method: type
                    @receive new Robot.TextMessage user, msg
            else
                @bot.on type, (name, msg) =>
                    @robot.logger.debug "#{name} #{type}ed: #{msg}"
                    user = @userForId name, method: type
                    @receive new Robot.TextMessage user, "#{@robot.name} #{msg}"

        @bot.listen()
        @emit "connected"

    send: (user, strings...) ->
        for string in strings
            if '\n' in string
                @robot.logger.debug "sending paste"
                if method is 'whisper' or 'help'
                    @bot.speak "@pasteto2 #{user.name}"
                else
                    @bot.speak "@paste"
                for line in string.split '\n'
                    @bot.speak "#{line}"
                @bot.speak "."
            else
                @robot.logger.debug "sending message"
                if user.method is 'help' or 'whisper'
                    @bot.speak "mu #{user.name} #{string}"
                else
                    @bot.speak "#{user.name} #{string}"

    reply: (user, strings...) ->
        @robot.logger.debug "replying to #{user.name}"
        for string in strings
            @bot.speak "#{user.name}, #{string}"

    close: ->
        @bot.speak "@quit"

    topic: (user, strings...) ->
        Robot.logger.debug "Setting Topic"

class MooClient extends EventEmitter
    constructor: (options, @robot) ->
        unless options.host? and options.port? and options.user? and options.pass?
            @robot.logger.error "Not enough parameters provided.  Need host, port, user and pass."
            process.exit(1)

        {@host, @port, @user, @pass} = options
        @client = new net.Socket()

        # regular expressions to match input against
        @matchers =
            say: /^(.+) says, "(.+)"/
            direct: /^(.+) \[to you\]: (.+)/
            whisper: /^(.+) whispers to you, "(.+)"/
            #TODO: add page


    speak: (msg) ->
        @client.write "#{msg}\r\n"

    listen: ->
        @client.connect @port, @host, =>
            @speak "@connect #{@user} #{@pass}"
            @robot.logger.info "Connection established..."

        buffer = ""
        @client.on "data", (chunk) =>
            buffer += chunk
            lines = buffer.split "\r\n"
            buffer = lines.pop()
            lines.forEach (line) =>
                @robot.logger.debug line
                for type, matcher of @matchers
                    if matcher.test line
                        [name, msg] = matcher.exec(line)[1..2]
                        @robot.logger.debug "emitting #{type}"
                        if type is 'direct' and 'help' in msg
                            @emit 'help', name, msg
                        else
                            @emit type, name, msg

        @client.on "close", ->
            console.log "Connection closed by remote host, exiting."


exports.use = (robot) ->
    new Moo robot
