class CookieStore(T) < Store(T)
  property cookies = HTTP::Cookies.new
  getter cookie_name = "_data_"

  def storage : String
    self.class.name
  end

  def [](key : String) : SessionId(T)
    data = cookies[prefixed(cookie_name + key)] || raise InvalidSessionExeception.new
    deserialize_session(data.value)
  end

  def []?(key : String) : SessionId(T)?
    if data = cookies[prefixed(cookie_name + key)]?
      deserialize_session(data.value)
    end
  end

  def []=(key : String, session : SessionId(T)) : SessionId(T)
    cookies << create_session_cookie(key, session)
    session
  end

  def delete(key : String)
    cookies.delete(prefixed(cookie_name + key))
  end

  def size : Int64
    count_cookies(prefixed(cookie_name))
  end

  def clear
    cookies.reject! { |cookie| cookie.name.starts_with?(prefixed(cookie_name)) }
  end

  private

  def create_session_cookie(key : String, session : SessionId(T))
    HTTP::Cookie.new(
      name: prefixed(cookie_name + key),
      value: encrypt_and_sign(session.to_json),
      expires: timeout.from_now,
      secure: true,
      http_only: true,
      creation_time: Time.local
    )
  end

  def deserialize_session(value : String) : SessionId(T)
    SessionId(T).from_json(verify_and_decrypt(value))
  end

  def count_cookies(name_prefix : String) : Int64
    cookies.reduce(0_i64) { |acc, cookie| acc + 1 if cookie.name.starts_with?(name_prefix) }
  end
end
end
