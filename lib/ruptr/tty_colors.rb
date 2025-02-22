# frozen_string_literal: true

module Ruptr
  class TTYColors
    def self.probably_ansi_terminal?(io) = io.tty? && !['dumb', 'unknown', ''].include?(ENV.fetch('TERM', ''))
    def self.want_cli_colors? = ENV.include?('CLICOLOR') || ENV.include?('LS_COLORS')
    def self.for(io) = (want_cli_colors? && probably_ansi_terminal?(io) ? ANSICodes : Dummy).new

    def self.seems_to_contain_formatting_codes?(s) = s.match?(/[\e\b]/)

    class Dummy < self
      def supports?(*args) = args.empty?
      def wrap(s, **_opts) = s.to_s
    end

    class Overstrike < self
      SUPPORTED = %i[bright underline].freeze

      def supports?(*args) = args.all? { |name| SUPPORTED.include?(name) }

      def wrap(s, bright: nil, underline: nil, **_opts)
        s.to_s.chars.map { |c| %(#{c}#{bright ? "\b#{c}" : ''}#{underline ? "\b_" : ''}) }.join
      end
    end

    class ANSICodes < self
      SUPPORTED = %i[bright faint italic underline reverse strike overstrike].freeze
      COLORS = %i[black red green yellow blue magenta cyan white].freeze

      def supports?(*args)
        args.all? do |name|
          case name
          when :color, :bg_color then COLORS.include?(name)
          else SUPPORTED.include?(name)
          end
        end
      end

      def wrap(s, **opts)
        b = +''; e = +''
        if opts[:bright] then b << "\e[1m"; e << "\e[22m" end
        if opts[:faint] then b << "\e[2m"; e << "\e[22m" end
        if opts[:italic] then b << "\e[3m"; e << "\e[23m" end
        if opts[:underline] then b << "\e[4m"; e << "\e[24m" end
        if opts[:reverse] then b << "\e[7m"; e << "\e[27m" end
        if opts[:strike] then b << "\e[9m"; e << "\e[29m" end
        if opts[:overstrike] then b << "\e[53m"; e << "\e[55m" end
        if (color_index = COLORS.find_index(opts[:color]))
          b << "\e[#{30 + color_index}m"
          e << "\e[39m"
        end
        if (color_index = COLORS.find_index(opts[:bg_color]))
          b << "\e[#{40 + color_index}m"
          e << "\e[49m"
        end
        "#{b}#{s}#{e}"
      end
    end
  end
end
