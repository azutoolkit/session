require "redis"

module Session
  class CookieStore(T) < Store(T)
    property cookies = HTTP::Cookies.new
    getter cookie_name = "_data_"

    # Gets the session manager store type
    def storage : String
      self.class.name
    end

    def [](key : String) : SessionId(T)
      if data = cookies[prefixed(cookie_name + key)]
        payload = String.new(verify_and_decrypt(data.value))
        SessionId(T).from_json payload
      else
        raise InvalidSessionExeception.new
      end
    end

    def []?(key : String) : SessionId(T)?
      if data = cookies[prefixed(cookie_name + key)]?
        payload = String.new(verify_and_decrypt(data.value))
        SessionId(T).from_json payload
      end
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      cookies << HTTP::Cookie.new(
        name: prefixed(cookie_name + session.session_id),
        value: encrypt_and_sign(session.to_json),
        expires: timeout.from_now,
        secure: true,
        http_only: true,
        creation_time: Time.local,
      )
      session
    end

    def delete(key : String)
      cookies.delete prefixed(cookie_name + key)
    end

    def size : Int64
      name = prefixed(cookie_name)
      cookies.reduce(0_i64) do |acc, cookie|
        acc + 1 if cookie.name.starts_width? name
      end
    end

    def clear
      cookies.each do |cookie|
        cookies.delete cookie.name if cookie.name.starts_width? name
      end
    end
  end
end
