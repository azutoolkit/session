module Session
  class Configuration
    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
    property on_started : Proc(String, Nil) = ->(sid : String) {}
    property on_deleted : Proc(String, Nil) = ->(sid : String) {}
  end
end
