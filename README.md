# aws_info
ruby version of the aws cli uses awscosts gem to get costing.   

aws_info essentially duplicates the functions available from the 
aws cli, but with a couple of caveats:
1.  All regions are queried by default
2.  All assets are queried by default
3.  Costs are added to output (with the --price option)

##Prerequisites
You'll need the aws-sdk ruby gem installed, and if you use pricing, the aws_pricing gem (awscosts).

##Example
So, this command for example:

aws_info -prock -t -price

would attempt to describe all assets owned by the account described in 
the "rock" profile, in all regions, where possible printing all tags
(the -t option), and again where possible, list pricing info for each
asset.

##What AWS assets can aws_info describe?

This shows each command-line option, and what it will cause to be listed:
* -a              : all assets (the default, anyway, so this is superfluous)
* -ami            : AMIs
* -instances      : EC2 Instances (stopped & running)
* -igw            : Internet Gateways
* -lb             : loadbalancers
* -nats           : NAT gateways
* -nacl           : NACLs
* -route          : Route Tables
* -rds            : RDS Clusters/Instances
* -key            : Key Pairs
* -subnet         : Subnets
* -snapshots      : Snapshots
* -s3             : S3 Buckets
* -volumes        : Volumes
* -eip            : Elastic IPs
* -efs            : Elastic Filesystems
* -vpcs           : VPCs
* -security       : Security Groups
* -redshift       : Redshift Clusters
* -elasticache    : Elasticache nodes
* -users          : IAM Users
* -limits         : Attempts to get limits for each region

##Extra opions
If -t is given on the command-line, tags are added after the basic info about each taggable asset.  Note, that
this is always after the basic info, so that the field-order is preserved.
The --price option adds pricing info where useful - principally in the case of EC2 Instances.
By default, assets are shown from all regions (Which appallingly is a hard-coded array of region names).  By
specifying --region [region_name], the search is restricted to that region.
Some actions will fail with insufficient permissions.  The default behaviour in that case is to exit; this can be overridden
by specifying -nofail.

## Examples of Usage:

####Want to generate a _fairly_ complete list of assets in your account?

~~~~
aws_info -p[account_name] -audit
~~~~

Which will create a directory in the current directory, with the name of the profile [account_name], and under
that a timestamped directory (so you could keep an audit over time), and in there, a directory for each region, as well
as one for "all", for assets which are global.  Within each directory, a file will be created for each asset type.
eg:

~~~~
$ aws_info -pprod_account -audit
~~~~
[_long_ wait]  <- it's iterating over each region for each asset type
~~~~
$ tree
├── prod_account/
│   └── 20170626091308/
│       ├── all/
│       │   ├── s3_buckets
│       │   └── users
│       ├── ap-northeast-1/
│       │   ├── amis
│       │   ├── efs
│       │   ├── eips
│       │   ├── elasticaches
│       │   ├── elbs
│       │   ├── igws
│       │   ├── instances
│       │   ├── keys
│       │   ├── limits
│       │   ├── nacls
│       │   ├── nat_gateways
│       │   ├── rds_instances
│       │   ├── redshift
│       │   ├── route_tables
│       │   ├── security_groups
│       │   ├── snapshots
│       │   ├── subnets
│       │   ├── volumes
│       │   └── vpcs
│       ├── ap-northeast-2/
│       │   ├── amis
│       │   ├── efs
│       │   ├── eips
│       │   ├── elasticaches
│       │   ├── elbs
│       │   ├── igws
│       │   ├── instances
│       │   ├── keys
│       │   ├── limits
│       │   ├── nacls
│       │   ├── nat_gateways
│       │   ├── rds_instances
│       │   ├── redshift
│       │   ├── route_tables
~~~~
... 

####Suppose you are planning a new subnet and wish to see which ones are already in use in the eu-west-1 region?

aws_info --subnets --region eu-west-1 would list all subnets in the region.  This could be piped to a 
Unix command-line to produce something like this:

~~~~
$ aws_info --region eu-west-1 --subnets | awk -F'\"*,\"*' '{gsub("\."," ",$7); print $7}' | sort -k1n -k2n -k3n | tr ' ' '.'
10.10.53.0/24
10.10.71.0/24
10.10.72.0/24
10.10.73.0/24
10.10.81.0/24
10.10.82.0/24
10.10.83.0/24
10.10.91.0/24
...
~~~~


####To get an idea of monthly running cost for all ec2 instances:

~~~~
$ aws_info -i -price
~~~~

Would list the instances (both running and stopped) with their hourly price cost.  For a stopped instance, the script sets
an hourly cost of $0.00. 

~~~~
$ aws_info -price -i 
"default","Instance","eu-west-1","i-0f8bfc2de054a2b8a","running","c4.large","ami-db9ae0a8","vpc-27a7e143","0.113"
"default","Instance","eu-west-1","i-0e06755088fbc42b0","running","t2.medium","ami-6ac41b19","vpc-0f0e316a","0.05"
"default","Instance","eu-west-1","i-0a4dace8b125b5f77","running","t2.medium","ami-6ac41b19","vpc-1839007d","0.05"
"default","Instance","eu-west-1","i-009b3abf5d3f1ddeb","running","t2.medium","ami-6ac41b19","vpc-0f0e316a","0.05"
"default","Instance","eu-west-1","i-0d4b9e72b0c9eccf8","running","m3.large","ami-6ac41b19","vpc-a50e31c0","0.146"
"default","Instance","eu-west-1","i-0d5d983ea9d592c38","running","t2.medium","ami-3e131058","vpc-ef2cd388","0.05"
"default","Instance","eu-west-1","i-0528bbfe65996c5ed","running","t2.medium","ami-6ac41b19","vpc-a50e31c0","0.05"
"default","Instance","eu-west-1","i-77638d46","running","t2.nano","ami-bb5ec5c8","vpc-693a460c","0.0063
~~~~

It's then simple to pipe this to an awk script (there are approx 780 hours in a month):

~~~~
$ aws_info -pan_account -i  -price | awk -F'\"*,\"*' '{costs[$6]+=$9;count[$6]+=1 ; tot=tot+$9; inst_count+=1} END { for (size in costs) { printf("%-17s %3d %9.1f\n",size,count[size],costs[size]*780)} ; printf("%-17s %3d %9.1f\n","Totals:",inst_count, tot*780) }'

c4.2xlarge         44   14486.9
t2.small            1      19.5
t2.large            4     315.1
m4.large            6     432.9
m3.large            2     227.8
r4.xlarge           1     230.9
m4.xlarge          15    2424.2
c4.large           12    1057.7
c3.large            8     748.8
r4.2xlarge          8    3700.3
c4.xlarge         119   20977.3
t2.medium         115    4407.0
t2.micro           88     892.3
m4.2xlarge         11    3809.5
m3.medium          42    2391.5
Totals:           476   56121.8
~~~~


#### Listing all users without MFA enabled
~~~~
$ aws_info --users | awk -F'\"*,\"*' '$NF ~ /no/ {print $5}'
r.walker@XXX.com
pamelap
rob.jones@xxx.com
...
~~~~

#### List all assets tagged with a particular string
~~~~
$ aws_info -t | grep "_SOME-STRING_"
~~~~
-eg:

~~~~
$ aws_info -t | egrep -i "env(ironment)?:pro?d"
"default","Security Group","eu-west-1","sg-fc268285","vpc-eb09b38e","prd-project2-PRI-frontend-blue-SG"","Application:project2"","Environment:prd"","Name:prd-project2-PRI-frontend-blue-SG"","Role:frontend-blue"","Tier:PRI"
"default","Security Group","eu-west-1","sg-ffed7f9b","vpc-774f2a12","Define access to API PRD nodes"","environment:prd-projecth"","project:projecth"
"default","NACL","eu-west-1","acl-5108a235","vpc-37f2e652","false","1","Name:tableau-acl-prd-tableau_google_api","component:tableau","environment:prd-tableau","project:project2-tableau"
"default","NACL","eu-west-1","acl-d837c7bc","vpc-37f2e652","false","3","Name:tableau-acl-rds-prd-tableau","component:tableau","environment:prd-tableau","project:project2-tableau"
"default","NACL","eu-west-1","acl-5008a234","vpc-37f2e652","false","1","Name:tableau-acl-prd-tableau","component:tableau","environment:prd-tableau","project:project2-tableau"
...
~~~~


## Pricing
Somebody much smarter than me has written a ruby gem to get the AWS pricing.  You'll need that installed _only if you use the
--price command-line option_, as I only require the module if --pricing is specified.  This makes the program more portable.


## Is it any use?

I've no idea if _you_ will find it useful - I do. I'm well aware that you can do most (and more) of what aws_info can do using the aws 
CLI tools, but
1.  The tools are difficult to get output in a clear format from.
2.  The tools would still need to be wrapped to work across the whole estate of regions.
3.  It's easier to extend a tool which you have the source for.
4. 


##Bugs
Yep.  There's bug included.  For free. Fork 'em.
For instance, the region-list is hardcoded - which is awful, and ironic, considering that the whole crux of the thing is programmatic access.  Feel free to fix this, as well as allowing the --region= option to take a comma-separated list of regions.


##Style
Too many globals.  I'd like to tidy up the code - I got started thinking I'd just list instances, but found the
CSV output format so useful that I kept adding things.  Fork it.

