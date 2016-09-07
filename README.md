# MongoDB Replica Set Cookbook

# Requirements
Access to AWS EC2, Autoscaling group and Route 53. Proper traffic rules and roles configurations.

# Attributes
This cookbook works with AWS Autoscaling group to self-heal. When one node goes down, the autoscaling group would 
automatically stand up a new node, and this cookbook will perform all the steps required to add the new node to 
the replica set. Thus a replica set can automatically set up itself and self-heal without any human interference. <br />
All the system tuning is included according to instruction (https://docs.mongodb.com/ecosystem/platforms/amazon-ec2/), 
assuming MongoDB is running on Amazon Linux.

# Usage
* Fill out the default variables in attributes/default.rb <br />
* Go to AWS Console - EC2 - AUTO SCALING - Launch Configurations, click "Create launch configuration" 
* Set up proper steps in user data to run this cookbook.
* On Step 4: Add three new volumes: /dev/sdg, /dev/sdf, /dev/sdh. <br />
Choose proper size for each of them, sdf is for data, sdh is for journal, sdg is for log
* Once finished creating launch config, create an autoscaling group out of the launch config.
* Launch!

# License and Author
* Author: Fangyi Zhu (fangyizhu416@gmail.com)
* License: GPL V2 (https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
