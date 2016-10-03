# Install AWS Ruby SDK and MiniTest
#-----------------------------------------------------
chef_gem 'aws-sdk' do
  action :nothing
end.run_action(:install)

require 'aws-sdk'
Chef::Recipe.send(:include, MongoDB::Helper)

# Choose current instance id
#-----------------------------------------------------
instance_id = `curl http://169.254.169.254/latest/meta-data/instance-id`
replica_set = get_instance_autoscaling_group(node['region'], instance_id)

# Randomize waiting time to best avoid ID conflict
wait_time = rand(1..60)
sleep(wait_time)
mongo_id = pick_current_instance_id(node['region'], instance_id)
sleep(wait_time)

while get_existing_mongo_ids(node['region'], replica_set).include? mongo_id do
  puts "#{mongo_id} already exists in ASG. Picking a new one."
  mongo_id = pick_current_instance_id(node['region'], instance_id)
  sleep(15)
end

tag_name(node['region'], instance_id, replica_set + '-' + mongo_id)


# Create service script
#-----------------------------------------------------
ip_address = `curl http://169.254.169.254/latest/meta-data/local-ipv4`
mongo_dns = "#{replica_set}-#{mongo_id}.#{node['cluster_dns']}"


# update DNS record for Server
#-----------------------------------------------------
template '/tmp/dns_upsert.json' do
  source 'dns_upsert.json.erb'
  mode   '0744'
  variables :mongo_dns => mongo_dns,
            :instance_id => instance_id,
            :new_ip => ip_address
  action :create
end

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
  variables :rpl_set => replica_set
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
#---------------git --------------------------------------
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

# Set slaveOK in mongorc.js
#-----------------------------------------------------
template '/etc/mongorc.js' do
  source 'mongorc.js.erb'
  mode '0744'
end

# Start Mongodb
#-----------------------------------------------------
service 'mongod' do
  action :start
end

# Initiate a replica set, or add self to an existing one
#-----------------------------------------------------
rs_command = replica_set_command(node['region'], replica_set, mongo_dns)
puts(rs_command)
execute 'replica_set' do
  command rs_command
  action :run
end

# Mark instance in replica set by putting a mongo_id tag on it
#-----------------------------------------------------
ruby_block 'tag_mongo_id' do
  block do
    ec2 = Aws::EC2::Client.new(region: node['region'])
    ec2.create_tags(resources: [instance_id], tags: [{key: 'mongo-id', value: mongo_id}])
  end
  action :run
end

