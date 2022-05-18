module Session
  class Configuration
    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
    property on_started : Proc(String, Databag, Nil) = ->(sid : String, data : Session::Databag) {}
    property on_deleted : Proc(String, Databag, Nil) = ->(sid : String, data : Session::Databag) {}
  end
end
