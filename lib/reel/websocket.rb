require 'websocket_parser'

module Reel
  class WebSocket
    include ConnectionMixin
    include RequestMixin

    def initialize(http_parser, socket)
      @http_parser, @socket = http_parser, socket

      handshake = ::WebSocket::ClientHandshake.new(:get, url, headers)

      if handshake.valid?
        response = handshake.accept_response
        response.render(socket)
      else
        error = handshake.errors.first

        response = Response.new(400)
        response.reason = handshake.errors.first
        response.render(@socket)

        raise HandshakeError, "error during handshake: #{error}"
      end

      @parser = ::WebSocket::Parser.new

      @parser.on_close do |status, reason|
        # According to the spec the server must respond with another
        # close message before closing the connection
        @socket << ::WebSocket::Message.close.to_data
        close
      end

      @parser.on_ping do
        @socket << ::WebSocket::Message.pong.to_data
      end

      @error_handlers = []
    end

    def read
      @parser.append @socket.readpartial(Connection::BUFFER_SIZE) until msg = @parser.next_message
      msg
    rescue => e
      @error_handlers.any? ?
        @error_handlers.each {|h| h.call e} :
        raise(e)
    end

    def body
      nil
    end

    def write(msg)
      @socket << ::WebSocket::Message.new(msg).to_data
      msg
    rescue => e
      @error_handlers.any? ?
        @error_handlers.each {|h| h.call e} :
        raise(e)
    end
    alias_method :<<, :write

    def closed?
      @socket.closed?
    end

    def close
      @socket.close
    end

    def on_error &proc
      @error_handlers << proc
      self
    end

  end
end
