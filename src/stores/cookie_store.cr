module Session
  class CookieStore(T) < Store(T)
    property cookies = HTTP::Cookies.new

    def storage : String
      self.class.name
    end

    def [](key : String) : SessionId(T)
      data = cookies[prefixed(cookie_name + key)] || raise InvalidSessionExeception.new
      deserialize_session(data.value)
    end

    def [](key : String) : SessionId(T)
      if data = cookies[data_key]
        payload = String.new(verify_and_decrypt(data.value))
        SessionId(T).from_json payload
      else
        raise InvalidSessionExeception.new
      end
    end

    def []?(key : String) : SessionId(T)?
      if data = cookies[data_key]?
        payload = String.new(verify_and_decrypt(data.value))
        SessionId(T).from_json payload
      end
    end

    def []=(key : String, session : SessionId(T)) : SessionId(T)
      cookies << HTTP::Cookie.new(
        name: data_key,
        value: encrypt_and_sign(session.to_json),
        expires: timeout.from_now,
        secure: true,
        http_only: true,
        creation_time: Time.local,
      )
      session
    end

    def delete(key : String)
      cookies.delete(data_key)
    end

    def size : Int64
      name = data_key
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
