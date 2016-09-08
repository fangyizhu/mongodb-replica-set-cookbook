# The name of your replica set, this should also be the name of the autoscaling group
default['mongo_set']=

# cluster_dns should be something like "somecompany.com", the final DNS record will be:
# mongo_set.cluster_dns
default['cluster_dns']=

# AWS Zone
default['region']=

# Route 53 zone ID
default['hosted_zone_id']=

default['tcp_keepalive_time']=240