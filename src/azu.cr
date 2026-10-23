# Opt-in integration for Azu (or any `HTTP::Server` app): `require "session/azu"`.
#
# ```
# require "session/azu"
#
# class UserSession < Session::Base
#   property user_id : Int64? = nil
# end
#
# Session::Web.use_store(Session::CookieStore(UserSession))
#
# Session.configure do |config|
#   config.secret = ENV["SESSION_SECRET"]
#   config.store = Session::CookieStore(UserSession).new
# end
#
# handlers = [Session::SessionHandler.new(Session.session)] of HTTP::Handler
# ```
#
# Then, in an endpoint (or anywhere a request's `HTTP::Server::Context` is at hand):
#
# ```
# context.session.user_id = 1_i64   # the typed session of this request
# context.flash["notice"] = "Saved" # shown on the next request, once
# ```
require "./session"

module Session::Web
  # Declares the session type and its store (`Session.use_store`) and adds the typed
  # `HTTP::Server::Context#session` and `HTTP::Server::Context#flash` accessors.
  macro use_store(store_type)
    Session.use_store({{ store_type }})
    Session::Web.accessors({{ store_type.resolve.type_vars.first }})
  end

  # Adds `HTTP::Server::Context#session` (typed as `session_type`) and `#flash`. They read the
  # current request's session, so they are only meaningful behind a `Session::SessionHandler`.
  # Call it after `Session.use_store`.
  macro accessors(session_type)
    class ::HTTP::Server::Context
      def session : {{ session_type }}
        ::Session.session.current_session
      end

      def flash : ::Session::Flash
        ::Session.session.flash
      end
    end
  end
end
