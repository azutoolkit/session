module Session
  class Configuration
    property timeout : Time::Span = 1.hour
    property session_key : String = "_session"
  end
end
