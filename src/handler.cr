module Session
  class SessionHandler
    include HTTP::Handler

    def initialize(@session)
    end

    def call(context : HTTP::Server::Context)
      @session.load_from session_cookie(context)
      call_nex(context)
      context.response.cookies << @session.cookie
    end

    def session_cookie(context)
      context.request.cookies[@session.session_key]
    end
  end
end
