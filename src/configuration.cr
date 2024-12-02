module Session
  class Configuration
    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
    property secret : String = "1sxc1aNxGHTTZKlK5cpCgufJAqGM4G13"
    property on_started : Proc(String, SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session started - SessionId: #{sid} Data: #{data}" }
    end
    property on_deleted : Proc(String, SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session deleted - SessionId: #{sid} Data: #{data}" }
    end
    property on_loaded : Proc(String, SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session loaded - SessionId: #{sid} Data: #{data}" }
    end
    property on_client : Proc(String, SessionData, Nil) = ->(sid : String, data : Session::SessionData) do
      Log.debug { "Session accessed - SessionId: #{sid} Data: #{data}" }
    end

    property provider : Provider? = nil

    def session
      provider.not_nil!
    end

    def encryptor
      Message::Encryptor.new(secret)
    end
  end
end
