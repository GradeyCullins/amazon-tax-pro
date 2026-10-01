if Gem.win_platform?
  module LocalWindowsTemplateGlob
    private

    def template_glob(glob)
      query = File.join(escape_entry(@path), glob)
      root = Rails.root.to_s.tr("\\", "/")
      query = query.delete_prefix("#{root}/") if query.start_with?("#{root}/")
      path_with_slash = File.join(@path, "")

      Dir.glob(query).filter_map do |filename|
        filename = File.expand_path(filename)
        next if File.directory?(filename)
        next unless filename.start_with?(path_with_slash)

        filename
      end
    end
  end

  ActionView::FileSystemResolver.prepend(LocalWindowsTemplateGlob)
end
