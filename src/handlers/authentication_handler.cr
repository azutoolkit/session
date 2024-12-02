module Session
  class AuthenticationHandler
    include HTTP::Handler

    def initialize(@session : Session::Provider, @signin_path : String, @whitelist : Regex)
    end

    def call(context : HTTP::Server::Context)
      if current_session.authenticated? || @whitelist.match(context.request.resource)
        call_next(context)
      else
        context.response.headers.add "Location", "#{@signin_path}?redirect_to=#{context.request.resource}"
        context.response.status_code = 302
      end
    end

    def current_session
      @session.current_session
    end
  end
end
