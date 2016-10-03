# MongoDB Replica Set Cookbook

# Requirements
Access to AWS EC2, Autoscaling group, Route 53 and S3. Proper traffic rules and roles configured.

# Attributes
This cookbook is supposed to work with AWS Autoscaling group. When one node goes down, the autoscaling group would 
automatically stand up a new node, and this cookbook will perform all the steps required to add the new node to 
the replica set automatically. Thus a replica set can set up itself and self-heal corrupted nodes without manual setup.<br />
The cookbook assumes and will make replica set name, autoscaling group name, instance name prefix, DNS record prefix
identical.

# Usage
* Fill out the default variables in attributes/default.rb <br />
* Go to AWS Console - EC2 - AUTO SCALING - Launch Configurations, click "Create launch configuration" 
* Set up proper steps in user data to run this cookbook.
* On Step 4: Add three new volumes: /dev/sdg, /dev/sdf, /dev/sdh. <br />
sdf is for data, sdh is for journal, sdg is for log
* Once finished creating launch config, create an autoscaling group out of the launch config.
* Launch!

# License and Author
* Author: Fangyi Zhu (fangyizhu416@gmail.com)
* License: GPL V2 (https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
