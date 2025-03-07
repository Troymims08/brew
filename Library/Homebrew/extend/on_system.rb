# typed: false
# frozen_string_literal: true

require "simulate_system"

module OnSystem
  extend T::Sig

  ARCH_OPTIONS = [:intel, :arm].freeze
  BASE_OS_OPTIONS = [:macos, :linux].freeze

  module_function

  sig { params(arch: Symbol).returns(T::Boolean) }
  def arch_condition_met?(arch)
    raise ArgumentError, "Invalid arch condition: #{arch.inspect}" if ARCH_OPTIONS.exclude?(arch)

    arch == Homebrew::SimulateSystem.current_arch
  end

  sig { params(os_name: Symbol, or_condition: T.nilable(Symbol)).returns(T::Boolean) }
  def os_condition_met?(os_name, or_condition = nil)
    if Homebrew::EnvConfig.simulate_macos_on_linux?
      return false if os_name == :linux
      return true if [:macos, *MacOSVersions::SYMBOLS.keys].include?(os_name)
    end

    return Homebrew::SimulateSystem.send("simulating_or_running_on_#{os_name}?") if BASE_OS_OPTIONS.include?(os_name)

    raise ArgumentError, "Invalid OS condition: #{os_name.inspect}" unless MacOSVersions::SYMBOLS.key?(os_name)

    if or_condition.present? && [:or_newer, :or_older].exclude?(or_condition)
      raise ArgumentError, "Invalid OS `or_*` condition: #{or_condition.inspect}"
    end

    return false if Homebrew::SimulateSystem.simulating_or_running_on_linux?

    base_os = MacOS::Version.from_symbol(os_name)
    current_os = MacOS::Version.from_symbol(Homebrew::SimulateSystem.current_os)

    return current_os >= base_os if or_condition == :or_newer
    return current_os <= base_os if or_condition == :or_older

    current_os == base_os
  end

  sig { params(method_name: Symbol).returns(Symbol) }
  def condition_from_method_name(method_name)
    method_name.to_s.sub(/^on_/, "").to_sym
  end

  sig { params(base: Class).void }
  def setup_arch_methods(base)
    ARCH_OPTIONS.each do |arch|
      base.define_method("on_#{arch}") do |&block|
        @on_system_blocks_exist = true

        return unless OnSystem.arch_condition_met? OnSystem.condition_from_method_name(__method__)

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end
  end

  sig { params(base: Class).void }
  def setup_base_os_methods(base)
    BASE_OS_OPTIONS.each do |base_os|
      base.define_method("on_#{base_os}") do |&block|
        @on_system_blocks_exist = true

        return unless OnSystem.os_condition_met? OnSystem.condition_from_method_name(__method__)

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end

    base.define_method(:on_system) do |linux, macos:, &block|
      @on_system_blocks_exist = true

      raise ArgumentError, "The first argument to `on_system` must be `:linux`" if linux != :linux

      os_version, or_condition = if macos.to_s.include?("_or_")
        macos.to_s.split(/_(?=or_)/).map(&:to_sym)
      else
        [macos.to_sym, nil]
      end
      return if !OnSystem.os_condition_met?(os_version, or_condition) && !OnSystem.os_condition_met?(:linux)

      @called_in_on_system_block = true
      result = block.call
      @called_in_on_system_block = false

      result
    end
  end

  sig { params(base: Class).void }
  def setup_macos_methods(base)
    MacOSVersions::SYMBOLS.each_key do |os_name|
      base.define_method("on_#{os_name}") do |or_condition = nil, &block|
        @on_system_blocks_exist = true

        os_condition = OnSystem.condition_from_method_name __method__
        return unless OnSystem.os_condition_met? os_condition, or_condition

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end
  end

  sig { params(_base: Class).void }
  def self.included(_base)
    raise "Do not include `OnSystem` directly. Instead, include `OnSystem::MacOSAndLinux` or `OnSystem::MacOSOnly`"
  end

  module MacOSAndLinux
    extend T::Sig

    sig { params(base: Class).void }
    def self.included(base)
      OnSystem.setup_arch_methods(base)
      OnSystem.setup_base_os_methods(base)
      OnSystem.setup_macos_methods(base)
    end
  end

  module MacOSOnly
    extend T::Sig

    sig { params(base: Class).void }
    def self.included(base)
      OnSystem.setup_arch_methods(base)
      OnSystem.setup_macos_methods(base)
    end
  end
end
