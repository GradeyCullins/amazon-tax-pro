# The git commit this app is running. Kamal sets KAMAL_VERSION to the deployed commit SHA (with an
# "_uncommitted_..." suffix for dirty builds); local servers ask git, rereading HEAD in development so the
# footer follows new commits without a restart.
module BuildInfo
  LENGTH = 8

  module_function

  def id
    sha = Rails.env.development? ? git_sha : (@sha ||= ENV["KAMAL_VERSION"].presence || git_sha)
    sha.to_s.first(LENGTH).presence || "unknown"
  end

  def git_sha
    output = IO.popen(["git", "-C", Rails.root.to_s, "rev-parse", "HEAD"], err: File::NULL, &:read)
    $?.success? ? output.strip : nil
  rescue SystemCallError
    nil
  end
end
