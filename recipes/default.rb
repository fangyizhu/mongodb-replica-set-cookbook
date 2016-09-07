# Install AWS Ruby SDK and MiniTest
#-----------------------------------------------------
chef_gem 'aws-sdk' do
  action :nothing
end.run_action(:install)

require 'aws-sdk'
Chef::Recipe.send(:include, MongoDB::Helper)

# Get current instance ID
#-----------------------------------------------------
instance_id = `curl http://169.254.169.254/latest/meta-data/instance-id`

# Tag current instance
#-----------------------------------------------------
tag = get_current_instance_tag(node['region'], node['mongo_set'], instance_id)

# Create service script
#-----------------------------------------------------
ip_address = `curl http://169.254.169.254/latest/meta-data/local-ipv4`
mongo_dns = "#{node['mongo_set']}-#{tag}.#{node['cluster_dns']}"

template '/tmp/dns_upsert.json' do
  source 'dns_upsert.json.erb'
  mode   '0744'
  variables :mongo_dns => mongo_dns,
            :instance_id => instance_id,
            :new_ip => ip_address
  action :create
end

# update DNS record for Server
#-----------------------------------------------------
execute 'upsert_dns_in_route53' do
  command "aws route53 change-resource-record-sets --hosted-zone-id #{node['hosted_zone_id']} --change-batch file:///tmp/dns_upsert.json"
  action :run
end

# Change hostname
#-----------------------------------------------------
execute 'change_hostname' do
  command "hostname #{mongo_dns}"
end

# add hostname to /etc/hosts
#-----------------------------------------------------
template '/etc/hosts' do
  source 'hosts.erb'
  mode '0744'
  variables :hostname => mongo_dns
end

# Configure yum
#-----------------------------------------------------
template '/etc/yum.repos.d/mongodb-org-3.2.repo' do
  source 'mongodb-org-3.2.repo.erb'
  mode '0744'
end

# Install MongoDB
#-----------------------------------------------------
package 'mongodb-org' do
  action :install
end

# Install xfsprogs
#-----------------------------------------------------
package 'xfsprogs' do
  action :install
end

# Configure logrotate
#-----------------------------------------------------
template '/etc/logrotate.d/mongod' do
  source 'mongod.erb'
  mode '0744'
end

# Configure TCP keepalive time
#-----------------------------------------------------
template '/etc/sysctl.conf' do
  source 'sysctl.conf.erb'
  mode '0744'
  variables :tcpKeepaliveTime => node['tcp_keepalive_time']
end

# Configure ELB read ahead settings
#-----------------------------------------------------
template '/etc/udev/rules.d/85-ebs.rules' do
  source '85-ebs.rules.erb'
  mode '0744'
end

# When creating instance, include the --ebs-optimized flag and specify individual EBS volumes
# /dev/xvdf for data, /dev/xvdg for journal, /dev/xvdh for log
# on EC2 launching, choose /dev/sdg, /dev/sdf, and /dev/sdh
#-----------------------------------------------------
if !::File.exist?('/data')
  ['/data', '/log', '/journal'].each do |mount_point|
    directory mount_point do
      mode '0755'
      owner 'mongod'
      group 'mongod'
      action :create
    end
  end

  ['/dev/xvdf', '/dev/xvdg', '/dev/xvdh'].each do |volume|
    execute "make_fs_#{volume}" do
      command "mkfs.xfs #{volume}"
      action :run
    end
  end

  mount 'data' do
    device '/dev/xvdf'
    fstype 'xfs'
    mount_point '/data'
    pass 0
    options 'defaults,auto,noatime,noexec'
    action [:enable,:mount]
  end

  mount 'log' do
    device '/dev/xvdg'
    fstype 'xfs'
    mount_point '/log'
    pass 0
    options 'defaults,auto,noatime,noexec'
    action [:enable, :mount]
  end

  mount 'journal' do
    device '/dev/xvdh'
    fstype 'xfs'
    mount_point '/journal'
    pass 0
    options 'defaults,auto,noatime,noexec'
    action [:enable, :mount]
  end

  link '/data/journal' do
    to '/journal'
  end

  directory '/data/db' do
    mode '0755'
    owner 'mongod'
    group 'mongod'
    action :create
  end

  # Change owner of the mount points
  ['/data', '/log', '/journal'].each do |mount_point|
    execute "change_owner_#{mount_point}" do
      command "chown -R mongod:mongod #{mount_point}"
    end
  end
end

# Configure MongoDB
#-----------------------------------------------------
template '/etc/mongod.conf' do
  source 'mongod.conf.erb'
  mode '0744'
  variables :mongo_set => node['mongo_set']
end

# Create mongo init.d event log file for booting and stopping events
#-----------------------------------------------------
file '/var/log/mongoevents' do
  mode '0755'
  owner 'mongod'
  group 'mongod'
  action :create
end

# Create mongodb.log and change the owner to mongod
#-----------------------------------------------------
file '/var/log/mongodb.log' do
  mode '0755'
  owner 'mongod'
  group 'mongod'
  action :create
end

# Change mongo init.d script
#-----------------------------------------------------
template '/etc/init.d/mongod' do
  source 'init.d_mongod.erb'
  mode '0744'
end

# Start Mongodb
#-----------------------------------------------------
service 'mongod' do
  action :start
end

# Initiate a replica set, or add self to an existing one
#-----------------------------------------------------
rs_command = replica_set_command(node['region'], node['mongo_set'], tag, mongo_dns)
puts "tag:"
puts tag
puts "mongo dns:"
puts mongo_dns
execute 'replica_set' do
  command rs_command
  action :run
end

# Tag self once being added to replica set
#-----------------------------------------------------
tag_self(node['region'], instance_id, tag, node['mongo_set'])