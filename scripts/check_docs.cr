require "file_utils"

# Type-checks the ```crystal blocks of the given Markdown files against this checkout, so the
# documentation cannot drift away from the API unnoticed.
#
#     crystal run scripts/check_docs.cr -- README.md UPGRADE.md docs/**/*.md
#
# A block is compiled with `--no-codegen` after a prelude (see `DocsCheck.prelude`) unless it
# requires the shard itself. A block that is only a fragment, or shows an API that no longer
# exists, opts out with `<!-- skip -->` on the line before its fence.
module DocsCheck
  record Snippet, file : String, line : Int32, source : String

  FENCE_OPEN = /\A```crystal\s*\z/
  SKIP_MARK  = "<!-- skip -->"
  WORKERS    = 4

  SESSION_CLASS = <<-CRYSTAL
    class UserSession < Session::Base
      property user_id : Int64? = nil
      property username : String? = nil
      property email : String? = nil
      property roles : Array(String) = [] of String
      property role : String = "guest"
      property login_time : Time? = nil

      def admin? : Bool
        role == "admin"
      end
      property logged_in_at : Time? = nil
    end

    CRYSTAL

  def self.snippets(file : String) : Array(Snippet)
    found = [] of Snippet
    lines = File.read_lines(file)
    index = 0
    while index < lines.size
      if lines[index].matches?(FENCE_OPEN)
        skipped = index > 0 && lines[index - 1].strip == SKIP_MARK
        start = index + 1
        index += 1
        body = [] of String
        while index < lines.size && lines[index].strip != "```"
          body << lines[index]
          index += 1
        end
        found << Snippet.new(file, start + 1, body.join('\n') + "\n") unless skipped
      end
      index += 1
    end
    found
  end

  # Variables the examples use without defining them.
  ASSUMED = {
    "store"          => "Session.session",
    "config"         => "Session.config",
    "session"        => "Session.session.current_session",
    "redis"          => "Redis.new",
    "session_id"     => %("a-session-id"),
    "compromised_id" => "42_i64",
    "request"        => %(HTTP::Request.new("GET", "/")),
    "response"       => "HTTP::Server::Response.new(IO::Memory.new)",
  }

  # The store a page documents: the block's own `config.store = ...`, else the one the page is about.
  def self.store_kind(snippet : Snippet) : String
    if configured = snippet.source.match(/config\.store = Session::(\w+Store)\(UserSession\)/)
      configured[1]
    elsif snippet.file.matches?(/cluster/)
      "ClusteredRedisStore"
    elsif snippet.file.includes?("redis-store") || snippet.file.includes?("circuit-breaker")
      "RedisStore"
    elsif snippet.file.includes?("cookie-store")
      "CookieStore"
    else
      "MemoryStore"
    end
  end

  # What a block may assume. Each block gets a prelude: the shard,
  # a `UserSession` class, `Session.use_store` for the store the page documents, and the variables of `ASSUMED`.
  def self.prelude(snippet : Snippet) : String
    source = snippet.source
    String.build do |io|
      io << %(require "session"\nrequire "redis"\n)
      io << SESSION_CLASS unless source.matches?(/class UserSession\b/)
      io << "Session.use_store(Session::#{store_kind(snippet)}(UserSession))\n" unless source.includes?("use_store")
      ASSUMED.each do |name, definition|
        io << name << " = " << definition << "\n" unless source.matches?(/\b#{name}\s*=[^=]/)
      end
    end
  end

  def self.program(snippet : Snippet) : String
    prelude(snippet) + snippet.source
  end

  # Returns nil when the snippet compiles, otherwise the compiler's first error line.
  def self.failure(snippet : Snippet, dir : String, id : Int32) : String?
    path = File.join(dir, "snippet_#{id}.cr")
    File.write(path, program(snippet))
    error = IO::Memory.new
    status = Process.run("crystal", ["build", "--no-codegen", "--no-color", path], error: error, output: Process::Redirect::Close)
    return if status.success?
    error.to_s.lines.find(&.starts_with?("Error")) || error.to_s.lines.first? || "compile failed"
  end

  # `require "session"` and `require "session/azu"` resolve like a shard in `lib/`: the temporary
  # directory holds a `session` link to this checkout.
  def self.run(files : Array(String)) : Int32
    root = Dir.current
    dir = File.tempname("session-docs-check")
    Dir.mkdir_p(dir)
    File.symlink(root, File.join(dir, "session"))
    ENV["CRYSTAL_PATH"] = "#{dir}:#{File.join(root, "lib")}:#{`crystal env CRYSTAL_PATH`.strip}"
    all = files.flat_map { |file| snippets(file) }

    results = Channel({Snippet, String?}).new
    queue = Channel({Snippet, Int32}).new
    WORKERS.times do
      spawn do
        while job = queue.receive?
          snippet, id = job
          results.send({snippet, failure(snippet, dir, id)})
        end
      end
    end
    spawn do
      all.each_with_index { |snippet, id| queue.send({snippet, id}) }
      queue.close
    end

    failed = all.compact_map do
      snippet, error = results.receive
      next unless error
      puts "#{snippet.file}:#{snippet.line}: #{error}"
      snippet
    end
    puts "#{all.size} snippets checked, #{failed.size} failed"
    failed.empty? ? 0 : 1
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end

exit DocsCheck.run(ARGV.to_a)
