#
# Cookbook Name:: apache2
# Recipe:: default
#
# Copyright 2008-2009, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package "apache2" do
  case node[:platform]
  when "redhat","centos","scientific","fedora","suse"
    package_name "httpd"
  when "debian","ubuntu"
    package_name "apache2"
  when "arch"
    package_name "apache"
  when "freebsd"
    package_name "apache22"
  end
  action :install
end

service "apache2" do
  case node[:platform]
  when "redhat","centos","scientific","fedora","suse"
    service_name "httpd"
    # If restarted/reloaded too quickly httpd has a habit of failing.
    # This may happen with multiple recipes notifying apache to restart - like
    # during the initial bootstrap.
    restart_command "/sbin/service httpd restart && sleep 1"
    reload_command "/sbin/service httpd reload && sleep 1"
  when "debian","ubuntu"
    service_name "apache2"
    restart_command "/usr/sbin/invoke-rc.d apache2 restart && sleep 1"
    reload_command "/usr/sbin/invoke-rc.d apache2 reload && sleep 1"
  when "arch"
    service_name "httpd"
  when "freebsd"
    service_name "apache22"
  end
  supports value_for_platform(
    "debian" => { "4.0" => [ :restart, :reload ], "default" => [ :restart, :reload, :status ] },
    "ubuntu" => { "default" => [ :restart, :reload, :status ] },
    "redhat" => { "default" => [ :restart, :reload, :status ] },
    "centos" => { "default" => [ :restart, :reload, :status ] },
    "scientific" => { "default" => [ :restart, :reload, :status ] },
    "fedora" => { "default" => [ :restart, :reload, :status ] },
    "arch" => { "default" => [ :restart, :reload, :status ] },
    "suse" => { "default" => [ :restart, :reload, :status ] },
    "freebsd" => { "default" => [ :restart, :reload, :status ] },
    "default" => { "default" => [:restart, :reload ] }
  )
  action :enable
end

if platform?("redhat", "centos", "scientific", "fedora", "arch", "suse", "freebsd")
  directory node[:apache][:log_dir] do
    mode 0755
    action :create
  end

  package "perl"

  cookbook_file "/usr/local/bin/apache2_module_conf_generate.pl" do
    source "apache2_module_conf_generate.pl"
    mode 0755
    owner "root"
    group node[:apache][:root_group]
  end

  %w{sites-available sites-enabled mods-available mods-enabled}.each do |dir|
    directory "#{node[:apache][:dir]}/#{dir}" do
      mode 0755
      owner "root"
      group node[:apache][:root_group]
      action :create
    end
  end

  execute "generate-module-list" do
    if node[:kernel][:machine] == "x86_64"
      libdir = value_for_platform("arch" => { "default" => "lib" }, "default" => "lib64")
    else
      libdir = "lib"
    end
    command "/usr/local/bin/apache2_module_conf_generate.pl /usr/#{libdir}/httpd/modules /etc/httpd/mods-available"
    action :run
  end

  %w{a2ensite a2dissite a2enmod a2dismod}.each do |modscript|
    template "/usr/sbin/#{modscript}" do
      source "#{modscript}.erb"
      mode 0755
      owner "root"
      group node[:apache][:root_group]
    end
  end

  # installed by default on centos/rhel, remove in favour of mods-enabled
  %w{ proxy_ajp auth_pam authz_ldap webalizer ssl welcome }.each do |f|
    file "#{node[:apache][:dir]}/conf.d/#{f}.conf" do
      action :delete
      backup false
    end
  end

  # installed by default on centos/rhel, remove in favour of mods-enabled
  file "#{node[:apache][:dir]}/conf.d/README" do
    action :delete
    backup false
  end
end

directory "#{node[:apache][:dir]}/ssl" do
  action :create
  mode 0755
  owner "root"
  group node[:apache][:root_group]
end

directory "#{node[:apache][:dir]}/conf.d" do
  action :create
  mode 0755
  owner "root"
  group node[:apache][:root_group]
end

directory node[:apache][:cache_dir] do
  action :create
  mode 0755
  owner "root"
  group "root"
end

template "apache2.conf" do
  case node[:platform]
  when "redhat", "centos", "scientific", "fedora", "arch"
    path "#{node[:apache][:dir]}/conf/httpd.conf"
  when "debian","ubuntu"
    path "#{node[:apache][:dir]}/apache2.conf"
  when "freebsd"
    path "#{node[:apache][:dir]}/httpd.conf"
  end
  source "apache2.conf.erb"
  owner "root"
  group node[:apache][:root_group]
  mode 0644
  notifies :restart, resources(:service => "apache2")
end

template "security" do
  path "#{node[:apache][:dir]}/conf.d/security"
  source "security.erb"
  owner "root"
  group node[:apache][:root_group]
  mode 0644
  backup false
  notifies :restart, resources(:service => "apache2")
end

template "charset" do
  path "#{node[:apache][:dir]}/conf.d/charset"
  source "charset.erb"
  owner "root"
  group node[:apache][:root_group]
  mode 0644
  backup false
  notifies :restart, resources(:service => "apache2")
end

template "#{node[:apache][:dir]}/ports.conf" do
  source "ports.conf.erb"
  owner "root"
  group node[:apache][:root_group]
  variables :apache_listen_ports => node[:apache][:listen_ports].map{|p| p.to_i}.uniq
  mode 0644
  notifies :restart, resources(:service => "apache2")
end

template "#{node[:apache][:dir]}/sites-available/default" do
  source "default-site.erb"
  owner "root"
  group node[:apache][:root_group]
  mode 0644
  notifies :restart, resources(:service => "apache2")
end

include_recipe "apache2::mod_status"
include_recipe "apache2::mod_alias"
include_recipe "apache2::mod_auth_basic"
include_recipe "apache2::mod_authn_file"
include_recipe "apache2::mod_authz_default"
include_recipe "apache2::mod_authz_groupfile"
include_recipe "apache2::mod_authz_host"
include_recipe "apache2::mod_authz_user"
include_recipe "apache2::mod_autoindex"
include_recipe "apache2::mod_dir"
include_recipe "apache2::mod_env"
include_recipe "apache2::mod_mime"
include_recipe "apache2::mod_negotiation"
include_recipe "apache2::mod_setenvif"
include_recipe "apache2::mod_log_config" if platform?("redhat", "centos", "scientific", "fedora", "suse", "arch", "freebsd")

apache_site "default" if platform?("redhat", "centos", "scientific", "fedora")

service "apache2" do
  action :start
end
