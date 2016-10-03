require 'mixlib/shellout'

module MongoDB
  module Helper
    MONGO_PORT = ':27017'
    RPL_SET_TAG = 'aws:autoscaling:groupName'
    NAME_TAG = 'Name'
    MONGO_TAG = 'mongo-id'

    def get_instance_autoscaling_group(region, instance_id)
      return get_instances_tag_values(region, RPL_SET_TAG, [instance_id])[0]
    end


    def instance_has_tag?(region, key, instance_id)
      ec2 = Aws::EC2::Client.new(region: region)
      resp = ec2.describe_instances({instance_ids: [instance_id]})
      resp.reservations[0].instances[0].tags.each do |tag|
        if tag.key == key
          return true
        end
      end
      return false
    end


    def get_autoscaling_description(region, autoscaling_name)
      autoscaling = Aws::AutoScaling::Client.new(region: region)
      resp = autoscaling.describe_auto_scaling_groups({auto_scaling_group_names: [autoscaling_name]})
      return resp.auto_scaling_groups[0]
    end


    def list_instances_in_austoscaling(autoscaling_description)
      existing_mongo_instances= []
      autoscaling_description.instances.each do |instance|
        existing_mongo_instances.push(instance.instance_id)
      end
      return existing_mongo_instances
    end


    def get_instances_tag_values(region, key, instance_ids)
      # return a list of tag value of a given list of instance IDs and a tag key
      tag_values = []
      ec2 = Aws::EC2::Client.new(region: region)
      resp = ec2.describe_instances({instance_ids: instance_ids})
      resp.reservations.each do |reservation|
        reservation.instances[0].tags.each do |tag|
          if tag.key == key
            tag_values.push(tag.value)
          end
        end
      end
      return tag_values
    end


    def get_existing_mongo_ids(region, rpl_set)
      instances_in_asg = list_instances_in_austoscaling(get_autoscaling_description(region, rpl_set))
      tag_values = get_instances_tag_values(region, NAME_TAG, instances_in_asg)
      return tag_values.map {|tag_value| tag_value.split('-')[-1]}
    end


    def get_existing_rpl_set_node_ids(region, rpl_set)
      instances_in_asg = list_instances_in_austoscaling(get_autoscaling_description(region, rpl_set))
      tag_values = get_instances_tag_values(region, MONGO_TAG, instances_in_asg)
      return tag_values
    end


    def make_id_collection(desired_capacity)
      # Return a set of possible tags according to desired capacity
      # tag is 3 char long string made by mongo id with leading zeros
      # host with id 3 would have tag "003", starting from "000"
      return [*0..desired_capacity-1].map {|num| num.to_s.rjust(3, '0')}
    end


    def pick_one_available_id(id_collection, existing_ids)
      return (id_collection - existing_ids).sample
    end


    def pick_current_instance_id(region, instance_id)
      unless instance_has_tag?(region, NAME_TAG, instance_id)
        rpl_set = get_instance_autoscaling_group(region, instance_id)
        autoscaling_description = get_autoscaling_description(region, rpl_set)
        desired_capacity = autoscaling_description.desired_capacity
        puts("desired_capacity: #{desired_capacity}")

        existing_mongo_ids = get_existing_mongo_ids(region, rpl_set)
        puts("existing_mongo_ids: #{existing_mongo_ids}")

        # Prepare list of possible tags
        tag_collections = make_id_collection(desired_capacity)
        puts("tag_collections: #{tag_collections}")

        tag = pick_one_available_id(tag_collections, existing_mongo_ids)
        puts("mongo_id tag value: #{tag}")
      end
      return tag
    end


    def replica_set_command(region, rpl_set, hostname)
      # extract id_tag from hostname
      id_tag = hostname.split('.')[0].split('-')[-1]

      # get an integer id from tag_id, "001" => 1
      id = id_tag.to_i

      # get number of votes, first 7 members get 1, the rests get 0
      if id < 7 then votes = 1 else votes = 0 end

      # get a list of hostnames of existing mongo instances
      existing_ids = get_existing_rpl_set_node_ids(region, rpl_set) - [id_tag]

      # get a list of hosts potentially exist in replica set
      seeds = existing_ids.map{|e_tag| (hostname.sub(id_tag, e_tag) + MONGO_PORT)}

      member_config = "{_id: #{id}, host: \"#{hostname}\", votes: #{votes} }"

      if seeds.length == 0
        rs_command = "echo 'rs.initiate({_id:\"#{rpl_set}\", members:[ #{member_config}]})' | mongo"
      else
        rs_command = "echo 'rs.add(#{member_config})' | mongo --host " + rpl_set + '/' + seeds.join(',')
      end

      return rs_command
    end


    def tag_instance(region, instance_id, key, value)
      ec2 = Aws::EC2::Client.new(region: region)
      ec2.create_tags(resources: [instance_id], tags: [{key: key, value: value}])
    end


    def tag_name(region, instance_id, name)
      tag_instance(region, instance_id, NAME_TAG, name)
    end


    def tag_mongo_id(region, instance_id, id_tag)
      tag_instance(region, instance_id, MONGO_TAG, id_tag)
    end
  end
end
