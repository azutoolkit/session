module Session
  class CookieStore(T) < Store(T)
    include Enumerable(HTTP::Cookie)

    property cookies

    def initialize(@cookies : HTTP::Cookies = HTTP::Cookies.new)
    end

    def each(&block : HTTP::Cookie -> _)
      cookies.each do |cookie|
        yield cookie if cookie.name.starts_with?(data_key)
      end
    end

    def storage : String
      self.class.name
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
      count.to_i64
    end

    def clear
      each { |cookie| cookies.delete(cookie.name) }
    end

    def create_data_cookie(session : SessionId(T), host : String = "") : HTTP::Cookie
      HTTP::Cookie.new(
        name: data_key,
        value: encrypt_and_sign(session.to_json),
        expires: timeout.from_now,
        secure: true,
        domain: host,
        path: "/",
        samesite: HTTP::Cookie::SameSite::Strict,
        http_only: true,
        creation_time: Time.local
      )
    end

    private def data_key
      "#{Session.config.session_key}._data_"
    end

    private def encrypt_and_sign(value)
      Session.config.encryptor.encrypt_and_sign(value)
    end

    private def verify_and_decrypt(value)
      Session.config.encryptor.verify_and_decrypt(value)
    end
  end
end
