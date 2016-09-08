require 'mixlib/shellout'

module MongoDB
  module Helper
    MONGOTAG = 'mongo_id'
    MONGOPORT = ':27017'

    def instance_has_tag?(region, instance_id)
      ec2 = Aws::EC2::Client.new(region: region)
      resp = ec2.describe_instances({instance_ids: [instance_id]})
      resp.reservations[0].instances[0].tags.each do |tag|
        if tag.key == MONGOTAG
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


    def get_existing_mongo_tags(region, mongo_set, key)
      instances_in_asg = list_instances_in_austoscaling(get_autoscaling_description(region, mongo_set))
      return get_instances_tag_values(region, key, instances_in_asg)
    end


    def make_tag_collection(desired_capacity)
      # Return a set of possible tags according to desired capacity
      # tag is 3 char long string made by mongo id with leading zeros
      # host with id 3 would have tag "003"
      return [*0..desired_capacity-1].map {|num| num.to_s.rjust(3, '0')}
    end


    def pick_one_available_tag(tag_collection, existing_tags)
      return (tag_collection - existing_tags)[0]
    end


    def get_current_instance_tag(region, mongo_set, instance_id)
      unless instance_has_tag?(region, instance_id)
        autoscaling_description = get_autoscaling_description(region, mongo_set)
        desired_capacity = autoscaling_description.desired_capacity
        puts("desired_capacity: #{desired_capacity}")

        existing_mongo_tags = get_existing_mongo_tags(region, mongo_set, MONGOTAG)
        puts("existing_mongo_tags: #{existing_mongo_tags}")

        tag_collections = make_tag_collection(desired_capacity)
        puts("tag_collections: #{tag_collections}")

        tag = pick_one_available_tag(tag_collections, existing_mongo_tags)
        puts("mongo_id tag value: #{tag}")
      end
      return tag
    end


    def tag_instance(region, instance_id, key, value)
      ec2 = Aws::EC2::Client.new(region: region)
      ec2.create_tags(resources: [instance_id], tags: [{key: key, value: value}])
    end


    def replica_set_command(region, mongo_set, tag, hostname)
      # get id from tag
      id = tag.to_i

      # get number of votes, first 7 members get 1, the rests get 0
      if id < 7 then votes = 1 else votes = 0 end

      # get a list of hostnames of existing mongo instances
      existing_tags = get_existing_mongo_tags(region, mongo_set, MONGOTAG)

      # get a list of hosts potentially exist in replica set
      seeds = existing_tags.map{|e_tag| (hostname.sub(tag, e_tag)+MONGOPORT)}

      member_config = "{_id: #{id}, host: \"#{hostname}\", votes: #{votes}}"

      if seeds.length == 0
        rs_command = "echo 'rs.initiate({_id:\"#{mongo_set}\", members:[ #{member_config}]})' | mongo"
      else
        rs_command = "echo 'rs.add(#{member_config})' | mongo --host " + mongo_set + '/' + seeds.join(',')
      end

      return rs_command
    end


    def tag_self(region, instance_id, tag, mongo_set)
      # Tag instance for mongotag and name
      tag_instance(region, instance_id, MONGOTAG, tag)
      tag_instance(region, instance_id, 'Name', mongo_set + '-' + tag)
      puts("Tagged the current instance #{instance_id} with tag <mongo_id : #{tag}")
    end
  end
end
