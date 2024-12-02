module Session
  class SessionHandler
    include HTTP::Handler

    def initialize(@session : Session::Provider)
    end

    def call(context : HTTP::Server::Context)
      @session.load_from(context.request.cookies)
      call_next(context)
      @session.set_cookies(context.response.cookies, context.request.hostname.to_s)
    end

    private def generate_session_id
      UUID.random.to_s
    end
  end
end
