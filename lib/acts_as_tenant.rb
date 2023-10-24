require "request_store"

require "acts_as_tenant/version"
require "acts_as_tenant/errors"

module ActsAsTenant
  autoload :Configuration, "acts_as_tenant/configuration"
  autoload :ControllerExtensions, "acts_as_tenant/controller_extensions"
  autoload :ModelExtensions, "acts_as_tenant/model_extensions"
  autoload :TenantHelper, "acts_as_tenant/tenant_helper"

  CURRENT_TENANT = :current_tenant

  @@configuration = nil
  @@named_tenant_klasses = {}
  @@models_with_global_records = []
  @@mutable_named_tenants = {}

  class << self
    attr_writer :default_tenant
  end

  def self.configure
    @@configuration = Configuration.new
    yield configuration if block_given?
    configuration
  end

  def self.configuration
    @@configuration || configure
  end

  def self.set_named_tenant_klass(name, klass)
    @@named_tenant_klasses[name.to_sym] = klass
  end

  def self.named_tenant_klass(name)
    @@named_tenant_klasses[name.to_sym]
  end

  def self.models_with_global_records
    @@models_with_global_records
  end

  def self.add_global_record_model model
    @@models_with_global_records.push(model)
  end

  def self.fkey(name)
    "#{named_tenant_klass(name)}_id"
  end

  def self.pkey
    ActsAsTenant.configuration.pkey
  end

  def self.polymorphic_type(name)
    "#{named_tenant_klass(name)}_type"
  end

  def self.set_named_tenant(name, tenant)
    RequestStore.store[name.to_sym] = tenant
  end

  def self.named_tenant(name)
    RequestStore.store[name.to_sym]
  end

  def self.current_tenant=(tenant)
    set_named_tenant(CURRENT_TENANT, tenant)
  end

  def self.current_tenant
    named_tenant(CURRENT_TENANT) || test_tenant || default_tenant
  end

  def self.test_tenant=(tenant)
    Thread.current[:test_tenant] = tenant
  end

  def self.test_tenant
    Thread.current[:test_tenant]
  end

  def self.unscoped=(unscoped)
    RequestStore.store[:acts_as_tenant_unscoped] = unscoped
  end

  def self.unscoped
    RequestStore.store[:acts_as_tenant_unscoped]
  end

  def self.unscoped?
    !!unscoped
  end

  def self.default_tenant
    @default_tenant unless unscoped
  end

  def self.mutable_named_tenant!(name, toggle)
    @@mutable_named_tenants[name.to_sym] = toggle
  end

  def self.mutable_named_tenant?(name)
    @@mutable_named_tenants[name.to_sym]
  end

  def self.mutable_tenant!(toggle)
    mutable_named_tenant!(CURRENT_TENANT, toggle)
  end

  def self.mutable_tenant?
    mutable_named_tenant?(CURRENT_TENANT)
  end

  def self.with_tenant(tenant, &block)
    if block.nil?
      raise ArgumentError, "block required"
    end

    old_tenant = current_tenant
    self.current_tenant = tenant
    value = block.call
    value
  ensure
    self.current_tenant = old_tenant
  end

  def self.without_tenant(&block)
    if block.nil?
      raise ArgumentError, "block required"
    end

    old_tenant = current_tenant
    old_test_tenant = test_tenant
    old_unscoped = unscoped

    self.current_tenant = nil
    self.test_tenant = nil
    self.unscoped = true
    value = block.call
    value
  ensure
    self.current_tenant = old_tenant
    self.test_tenant = old_test_tenant
    self.unscoped = old_unscoped
  end

  def self.with_mutable_tenant(&block)
    ActsAsTenant.mutable_tenant!(true)
    without_tenant(&block)
  ensure
    ActsAsTenant.mutable_tenant!(false)
  end

  def self.should_require_tenant?
    if configuration.require_tenant.respond_to?(:call)
      !!configuration.require_tenant.call
    else
      !!configuration.require_tenant
    end
  end
end

ActiveSupport.on_load(:active_record) do |base|
  base.include ActsAsTenant::ModelExtensions
  require "acts_as_tenant/sidekiq" if defined?(::Sidekiq)
end

ActiveSupport.on_load(:action_controller) do |base|
  base.extend ActsAsTenant::ControllerExtensions
  base.include ActsAsTenant::TenantHelper
end

ActiveSupport.on_load(:action_view) do |base|
  base.include ActsAsTenant::TenantHelper
end
