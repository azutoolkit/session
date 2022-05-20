module Session
  class Configuration
    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
    property secret : String = "1sxc1aNxGHTTZKlK5cpCgufJAqGM4G13"
    property on_started : Proc(String, Databag, Nil) = ->(sid : String, data : Session::Databag) {}
    property on_deleted : Proc(String, Databag, Nil) = ->(sid : String, data : Session::Databag) {}

    def encryptor
      Message::Encryptor.new(secret)
    end
  end
end
