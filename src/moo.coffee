EventEmitter = require('events').EventEmitter
Adapter      = require('hubot').Adapter
Robot        = require('hubot').Robot
TextMessage  = require('hubot').TextMessage
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
        types = ['say', 'whisper', 'direct', 'page', 'help', 'action', 'indirect']

        types.forEach (type) =>
            @bot.on type, (name, msg) =>
                @robot.logger.debug "#{name}:#{type}: #{msg}"
                user = @userForId name
                if type in ['say', 'indirect']
                    user.replyMethod = 'say'
                    @receive new TextMessage user, msg
                else
                    user.replyMethod = type
                    @receive new TextMessage user, "#{@robot.name} #{msg}"

        @bot.listen()
        @emit "connected"

    send: (user, strings...) ->
        @robot.logger.debug "reply method: #{user.replyMethod}"
        for string in strings
            if string.search(/^EMOTE:/) == 0
                string = string.substr 6
                if user.replyMethod is 'whisper'
                    @bot.speak "+ #{user.name} " + string
                else
                    @bot.speak "emote " + string
            else if string.search(/^ECHO:/) == 0
                string = string.substr 5
                @bot.speak string
            else if '\n' in string
                @robot.logger.debug "sending paste"
                if user.replyMethod in ['page', 'whisper', 'help']
                    @bot.speak "@pasteto2 ~#{user.name}"
                else
                    @bot.speak "@paste"
                for line in string.split '\n'
                    @bot.speak "#{line}"
                @bot.speak "."
            else
                @robot.logger.debug "sending message"
                if user.replyMethod is 'action'
                    @bot.speak "#{string}"
                else if user.replyMethod is 'whisper'
                    @bot.speak "mu #{user.name} #{string}"
                else if user.replyMethod is 'page'
                    @bot.speak "page #{user.name} #{string}"
                else
                    @bot.speak "#{user.name}, #{string}"

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
            say: /^(\S+) says, "(.+)"/
            direct: /^(\S+) \[to you\]: (.+)/
            indirect: /^(\S+) \[to .*\]: (.+)/
            action: /^(mkemp) (?:whispers to you|pages), "DO (.+)"/
            whisper: /^(\S+) whispers to you, "(.+)"/
            page: /^(\S+) pages, "(.+)"/
            hi5: /^(\S+) hi5s you./ 
            poke: /^(\S+) pokes you./ 

    speak: (msg) ->
        @client.write "#{msg}\r\n"
        @robot.logger.debug "msg = #{msg}"

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
                for type, matcher of @matchers
                    if matcher.test line
                        [name, msg] = matcher.exec(line)[1..2]
                        if name is 'You'
                            break
                        #@robot.logger.debug "emitting #{type}"
                        #@robot.logger.debug "msg = #{msg}"
                        if type is 'action'
                            @speak msg
                        else if type is 'hi5'
                            @speak "hi5 #{name}"
                        else if type is 'poke'
                            @speak "emote coos like the Pillsbury Doughboy."
                        else
                            type = 'help' if type is 'direct' and /^h(ea)lp.*/.test msg
                            @emit type, name, msg
                        break

        @client.on "close", ->
            console.log "Connection closed by remote host, exiting."


exports.use = (robot) ->
    new Moo robot
