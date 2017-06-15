#!/usr/bin/env ruby
# Get info about all Resources in (the default) AWS estate
# Uses the default profile in the ~/.aws/credentials file.
# Graham Nicholls.  graham.nicholls@bjss.com 2017-04-11

require 'aws-sdk'

ABORTED=10
E_USAGE=11
E_AUTH_FAILURE=12
E_PROFILE_ERR=13
E_UNKNOWN_ERR=14

$regions=%w[ ap-south-1 eu-west-2 eu-west-1 ap-northeast-2 ap-northeast-1 sa-east-1 ca-central-1 ap-southeast-1 ap-southeast-2 eu-central-1 us-east-1 us-east-2 us-west-1 us-west-2 ]

def debug_msg(*words)
  if $debug
    $stderr.print("DEBUG: ")
    words.each do |word|
      $stderr.print("#{word} ")
    end
    $stderr.print("\n")
  end
  $stderr.flush()
end

def verbose_or_debug_msg(*words)
  if $debug
    debug_msg(*words)
    return
  end
  if $verbose 
    words.each do |word|
      $stderr.print("#{word} ")
    end
    $stderr.print("\n")
    $stderr.flush()
  end
end

def verbose_msg(*words)
  if $verbose
    words.each do |word|
      $stderr.print("#{word} ")
    end
    $stderr.print("\n")
  end
end

def err_msg(*words)
  words.each do |word|
    $stderr.print("#{word} ")
  end
  $stderr.print("\n")
end

def amis(region,my_id)
  verbose_or_debug_msg("Checking AMIs in region #{region} for profile #{$profile} owned by id #{my_id}")
  ec2 = Aws::EC2::Client.new(region: region,credentials: $credentials)
  result=ec2.describe_images( owners: [my_id ])
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/amis","w")
  else
    opfile=$stdout
  end
  result.images.each do |i|
    if not $quiet

      opfile.print("\"#{$profile}\",\"AMI\",\"#{region}\",\"#{i.image_id}\",\"#{i.root_device_type}\",\"#{i.name}\",\"#{i.description}\",\"\"#{i.platform == "windows" ? "windows" : "linux"}\"")

      if $print_tags
        i.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
          opfile.print(",\"#{tag.key}:#{tag.value}\"")
        end
      end
      opfile.print("\n")
    end
    $ami_count+=1
  end
end

def vpcs(region)
  verbose_or_debug_msg("Checking VPCs in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Client.new(region: region,credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/vpcs","w")
  else
    opfile=$stdout
  end

  ec2.describe_vpcs.each do |v|
    v.vpcs.each do |vpc|
    if not $quiet
      opfile.print("\"#{$profile}\",\"VPC\",\"#{region}\",\"#{vpc.vpc_id}\",\"#{vpc.cidr_block}\"")
      if $print_tags
        vpc.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
          opfile.print(",\"#{tag.key}:#{tag.value}\"")
        end
      end
      opfile.print("\n")
    end
    $vpc_count+=1
    end
  end
end

def subnets(region)
  verbose_or_debug_msg("Checking subnets in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Client.new(region: region,credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/subnets","w")
  else
    opfile=$stdout
  end
  ec2.describe_subnets.each do |s|
    s.subnets.each do |s|
      $subnet_count+=1
      if not $quiet
        opfile.print("\"#{$profile}\",\"Subnet\",\"#{region}\",\"#{s.subnet_id}\",\"#{s.vpc_id}\",\"#{s.availability_zone}\",\"#{s.cidr_block}\",\"#{s.default_for_az}\"")
        if $print_tags
          s.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
            opfile.print(",\"#{tag.key}:#{tag.value}\"")
          end
        end
        opfile.print("\n")
      end
    end
  end
end


def keys(region)
  verbose_or_debug_msg("Checking keys in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Client.new(region: region,credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/keys","w")
  else
    opfile=$stdout
  end
  ec2.describe_key_pairs.each do |kp|
    kp.key_pairs.each do |k|
      $key_count+=1
      if not $quiet
        opfile.print("\"#{$profile}\",\"Key Pair\",\"#{region}\",\"#{k.key_name}\",\"#{k.key_fingerprint}\"\n")
      end
    end
  end
end

#EC2 Instances
def ec2_instances(region)
  verbose_or_debug_msg("Checking running instances in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Resource.new(region: region,credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/instances","w")
  else
    opfile=$stdout
  end
  if $pricing
    verbose_or_debug_msg("Gathering instance pricing info for region #{region}")
    price_region = AWSCosts.region(region)
    if price_region != NIL
      prices=price_region.ec2.on_demand(:linux).price
    end
  end
  begin
    ec2.instances.each do |i|
      if i.state.name == "running" or i.state.name == "stopped"
        $running_i_count+=1 if i.state.name == "running"
        $stopped_i_count+=1 if i.state.name == "stopped"
        if not $quiet
          opfile.print "\"#{$profile}\",\"Instance\",\"#{region}\",\"#{i.id}\",\"#{i.state.name}\",\"#{i.instance_type}\",\"#{i.image_id}\",\"#{i.vpc_id}\""
          if $pricing 
            if price_region == NIL or i.state.name == "stopped"
              opfile.print(",\"\"")
            else
              opfile.print(",\"#{prices[i.instance_type]}\"")
            end
          end
          if $print_tags
            i.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
              opfile.print(",\"#{tag.key}:#{tag.value}\"")
            end
          end
          opfile.print("\n")
        end
      end
    end
  rescue Aws::EC2::Errors::AuthFailure =>err
    err_msg("Authentication failure for profile #{$profile} - (#{err}) - exiting\n")
    exit(E_AUTH_FAILURE)
  end
end

def ec2_volumes(region)
  verbose_or_debug_msg("Checking EC2 EBS volumes in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Resource.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/volumes","w")
  else
    opfile=$stdout
  end
  if $pricing
    verbose_or_debug_msg("Gathering EBS pricing info for region #{region}")
    price_region=AWSCosts.region(region)
    if price_region != NIL
      prices=price_region.ec2.ebs.price
      opfile.print prices
    end
  end
  ec2.volumes.each do |v|
    if v.state !~ /delet/
      if not $quiet
        opfile.print("\"#{$profile}\",\"Volume\",\"#{region}\",\"#{v.id}\",\"#{v.size}\",\"#{v.volume_type}\",\"#{v.state}\"")
        if $print_tags
          v.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
            opfile.print("\",\"#{tag.key}:#{tag.value}\"")
          end
        end
        opfile.print("\n")
      end
      $volume_count+=1
    end
  end
end

def ec2_snapshots(region,my_id)
  verbose_or_debug_msg("Checking snapshots in region \"#{region} owned by account id \"#{my_id}\"")
  ec2 = Aws::EC2::Resource.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/snapshots","w")
  else
    opfile=$stdout
  end
  snapshots=ec2.snapshots({filters: [{name: "owner-id", values: [ my_id ]}]})
  snapshots.each do |s|
    if not $quiet
      opfile.printf("\"#{$profile}\",\"Snapshot\",\"%s\",\"%s\",\"%s\",\"%s\"" ,region,s.id,s.volume_size,s.start_time.to_s)
      if $print_tags
        s.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
          opfile.print("\",\"#{tag.key}:#{tag.value}\"")
        end
      end
      opfile.print("\n")
    end
    $snap_count+=1
  end
end

def route_tables(region)
  verbose_or_debug_msg("Checking Route Tables in region \"#{region}\n")
  client = Aws::EC2::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/route_tables","w")
  else
    opfile=$stdout
  end
  client.describe_route_tables.each do |routes_array|
    routes_array.route_tables.each do |r|
      if not $quiet
        opfile.print("\"#{$profile}\",\"Route Table\",\"#{region}\",\"#{r.route_table_id}\",\"#{r.vpc_id}\",\"#{r.associations.length}\"")
        if $print_tags
          r.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
            opfile.print(",\"#{tag.key}:#{tag.value}\"")
          end
        end
        opfile.print("\n")
        $route_table_count+=1
      end
    end
  end
end

def nacls(region)
  verbose_or_debug_msg("Checking NACLs in region \"#{region}\n")
  client = Aws::EC2::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/nacls","w")
  else
    opfile=$stdout
  end
  client.describe_network_acls.each do |nacl_array|
    nacl_array.network_acls.each do |n|
      if not $quiet
        opfile.print("\"#{$profile}\",\"NACL\",\"#{region}\",\"#{n.network_acl_id}\",\"#{n.vpc_id}\",\"#{n.is_default}\",")
        opfile.print("\"#{n.associations.length}\"")
        if $print_tags
          n.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
            opfile.print(",\"#{tag.key}:#{tag.value}\"")
          end
        end
        opfile.print("\n")
        $nacl_count+=1
      end
    end
  end
end

def security_groups(region)
  verbose_or_debug_msg("Checking Security Groups in region \"#{region}\n")
  ec2 = Aws::EC2::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/security_groups","w")
  else
    opfile=$stdout
  end
  groups=ec2.describe_security_groups
  groups.security_groups.each do |s|
    if not $quiet
      opfile.print("\"#{$profile}\",\"Security Group\",\"#{region}\",\"#{s.group_id}\",\"#{s.vpc_id}\",\"#{s.description}\"")
      if $print_tags
        s.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
          opfile.print("\",\"#{tag.key}:#{tag.value}\"")
        end
      end
      opfile.print("\n")
    end
    $security_group_count+=1
  end
end

def rds_instances(region)
  verbose_or_debug_msg("Checking RDS instances in region \"#{region}\" for profile \"#{$profile}\"")
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/rds_instances","w")
  else
    opfile=$stdout
  end
  rds = Aws::RDS::Resource.new(region: region, credentials: $credentials)
  begin
    rds.db_instances.each do |r|
      if not $quiet
        opfile.print("\"#{$profile}\",\"Database\",\"#{region}\",\"#{r.id}\",\"#{r.db_name}\",\"#{r.db_instance_class}\",\"#{r.engine}\",\"#{r.db_subnet_group.vpc_id}\"")
        opfile.print("\n")
      end
      $rds_count+=1
    end
  rescue Aws::RDS::Errors::AccessDenied =>err 
    err_msg("Insufficient permissions failure for profile #{$profile} - (#{err})")
    if $continue_on_permissions_error
      return 
    else
      debug_msg("#{$continue_on_permissions_error}\n\n")
      err_msg("exiting\n")
      exit(E_AUTH_FAILURE)
    end
  rescue => err
    err_msg("An Unknown error has occurred #{err}")
    exit(E_UNKNOWN_ERR)
  end
end

def internet_gateways(region)
  verbose_or_debug_msg("Checking Internet gateways in region \"#{region}\" for profile \"#{$profile}\"")
  ec2 = Aws::EC2::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/igws","w")
  else
    opfile=$stdout
  end

  result = ec2.describe_internet_gateways()
  result.internet_gateways.each do |gw|
    if not $quiet
      opfile.print("\"#{$profile}\",\"Internet Gateway\",\"#{region}\",\"#{gw.internet_gateway_id}\"")
      gw.attachments.each do |a|
        opfile.print(",\"#{a.vpc_id}\"")
      end
      if $print_tags
        gw.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
          opfile.print("\",\"#{tag.key}:#{tag.value}\"")
        end
      end
      opfile.print("\n")
    end
    $igw_count+=1
  end
end

# Nat gateways don't currently support tags
def nat_gateways(region)
  verbose_or_debug_msg("Checking NAT gateways in region \"#{region}\" for profile \"#{$profile}\"")
  ec2 = Aws::EC2::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/nat_gateways","w")
  else
    opfile=$stdout
  end

  loop do 
    result = ec2.describe_nat_gateways()
    result.nat_gateways.each do |gw|
      if not $quiet
        opfile.print "\"#{$profile}\",\"NAT Gateway\",\"#{region}\",\"#{gw.vpc_id}\",\"#{gw.nat_gateway_id}\",\"#{gw.subnet_id}\"\n"
      end
      $gateway_count+=1
    end

    break if not result.next_token
  end
end

# IPSs don't currently support tags
def eips(region)
  verbose_or_debug_msg("Checking Elastic IPs in region \"#{region}\" for profile \"#{$profile}\"")
  ec2 = Aws::EC2::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/eips","w")
  else
    opfile=$stdout
  end


  result = ec2.describe_addresses()
  result.addresses.each do |add|
    if not $quiet
      opfile.print "\"#{$profile}\",\"EIP\",\"#{region}\",\"#{add.public_ip}\",\"#{add.association_id or 'None'}\"\n"
    end
    $eip_count+=1
  end
end

def load_balancers(region)
  verbose_or_debug_msg("Checking Load Balancers in region \"#{region}\" for profile \"#{$profile}\"")
  client = Aws::ElasticLoadBalancing::Client.new(region: region, credentials: $credentials)
  lbs=client.describe_load_balancers()
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/elbs","w")
  else
    opfile=$stdout
  end

  lbs.load_balancer_descriptions.each do |lb_desc|
    if not $quiet
      opfile.print "\"#{$profile}\",\"Load Balancer\",\"#{region}\",\"#{lb_desc.vpc_id}\",\"#{lb_desc.load_balancer_name}\",\"#{lb_desc.scheme}\""
      # TODO:
      #if $print_tags
        #lb_desc.tags.each do |tag|
          #print("\",\"#{tag.key}:#{tag.value}\"")
        #end
      #end
      opfile.print("\n")
    end
    $lb_count+=1
  end
end

# this is interesting: some buckets can only be accessed from a specific region.
# Handle this by using an array of buckets, and setting a flag to fund for each as it is found.
# Once all are found, 
def s3_info()
  verbose_or_debug_msg("Checking S3 resources in all regions  for profile \"#{$profile}\"")
  s3_resource=Aws::S3::Resource.new(region: "eu-west-1", credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/all/s3_buckets","w")
  else
    opfile=$stdout
  end
  
  # If we've not specified details, then simply list the buckets and return.
  if ! $s3_details
    s3_resource.buckets.each do |b|
      if not $quiet
        opfile.print("\"#{$profile}\",\"S3 Bucket\",\"All\",\"#{b.name}\",\"#{b.creation_date}\"\n")
      end
    $bucket_count+=1
    end
    return
  end
  
  # get a list of buckets:
  debug_msg("Generating a list of all buckets:\n")
  all_buckets=Hash.new()
  s3_resource.buckets.each do |bucket|
    all_buckets[bucket.name] = false
  end
  all_buckets.each do |b|
    debug_msg ("#{b}")
  end

  # Attempt to show all objects in each bucket - this is region-dependent - see comment above
  $regions.each do |region|
    begin
      s3_resource=Aws::S3::Resource.new(region: region, credentials: $credentials)
      s3_resource.buckets.each do |bucket|
        total_size=0
        if all_buckets[bucket.name] == false
          bucket.objects.each do |object|
            total_size+=object.size
          end
        end
        if not $quiet
          print("\"#{$profile}\",\"s3 bucket\",\"#{region}\",\"#{bucket.name}\",\"#{total_size}\"\n")
          all_buckets[bucket.name]=true
        end
      end
      $bucket_count+=1
    rescue Aws::S3::Errors::ServiceError => err
      debug_msg("#{err.inspect()}\n")
    end
  end
end

def efs(region)
  verbose_or_debug_msg("Checking EFS resources in region #{region} for profile \"#{$profile}\"")
  efs = Aws::EFS::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/efs","w")
  else
    opfile=$stdout
  end
  begin # EFS Not supported in all regions, so wrap in exception handling to deal with TCP connection failures
    efs.describe_file_systems.file_systems.each do |fs|
      if not $quiet
        opfile.print("\"#{$profile}\",\"EFS\",\"#{region}\",\"#{fs.creation_token}\",\"#{fs.file_system_id}\",\"#{fs.size_in_bytes['value']}\"")
        if $print_tags
          fs.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
            opfile.print("\",\"#{tag.key}:#{tag.value}\"")
          end
        end
        opfile.print("\n")
      end 
      $efs_count+=1
    end
  rescue => err
    # We ought to handle only the specific error of the region not having EFS, really.
    # print("Error in region #{region} #{err}\n")
    debug_msg("Error in region #{region} #{err}\n")
  end
end

# With elasticache we'll count clusters & cluster snapshots 
def elasticache(region)
  verbose_or_debug_msg("Checking Elasticache resources in region #{region} for profile \"#{$profile}\"")
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/elasticaches","w")
  else
    opfile=$stdout
  end
  begin
    elasticache = Aws::ElastiCache::Client.new(region: region, credentials: $credentials)
    clusters = elasticache.describe_cache_clusters()
    clusters.cache_clusters.each do |c|
      if not $quiet
        opfile.print("\"Elasticache Cluster\",\"#{region}\",\"#{c.cache_cluster_id}\",\"#{c.cache_node_type}\",\"#{c.engine}\"\n")
      end
      $elasticache_count+=1
    end
    snapshots=elasticache.describe_snapshots()
    snapshots.each do |ss|
      if not $quiet
        if ss.snapshots.length != 0
          opfile.print("\"#{$profile}\",\"Elasticache snapshot\",\"#{ss}\"\n") 
        end
      end
      $elasticache_snapshot_count+=1
    end
  rescue Aws::ElastiCache::Errors::AccessDenied =>err 
    err_msg("Insufficient permissions failure for profile #{$profile} - (#{err}) - exiting\n")
    if $continue_on_permissions_error
      return 
    else
      err_msg("exiting\n")
      exit(E_AUTH_FAILURE)
    end
  rescue => err
    err_msg("An Unknown error has occurred #{err}\n")
    exit(E_UNKNOWN_ERR)
  end
end

# TODO: Test with multiple clusters.  Several potential issues - firstly is the output paged so we only get (say) 50 
# results at a time?; secondly, not certain about the return structure.
def redshift(region)
  verbose_or_debug_msg("Checking Redshift resources in region #{region} for profile \"#{$profile}\"")
  efs = Aws::Redshift::Client.new(region: region, credentials: $credentials)
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/redshift","w")
  else
    opfile=$stdout
  end
  begin # Redshift is not supported by all regions
    efs.describe_clusters.each do |cluster|
      cluster.clusters.each do |c|
        if not $quiet
          # using a multiline broken string to preserve indentation:
          string="\"#{$profile}\",\"#{region}\",\"Redshift Cluster\",\"#{c.cluster_identifier}\",\"#{c.cluster_status}\",\"#{c.node_type}\",\""\
          "\"#{c.number_of_nodes}\",\"#{c.vpc_id}\""
          opfile.print string
        end 
        $redshift_count+=1
      end
    end
  rescue => err
    # We ought to handle only the specific error of the region not having EFS, really.
    # print("Error in region #{region} #{err}\n")
    debug_msg("Error in region #{region} #{err}\n")
  end
end

def users()
  verbose_or_debug_msg("Checking users for profile #{$profile}\n")
  iam = Aws::IAM::Client.new( region: "eu-west-1", credentials: $credentials)
  users=Array.new
  marker=nil
  if $audit_mode
    opfile=File.open("#{$audit_dir}/all/users","w")
  else
    opfile=$stdout
  end
  # Handle paginated results:
  begin
    loop do 
      debug_msg("Looping around users")
      resp=iam.list_users(marker: marker)
      resp.users.each do |user|
        users << user
      end
      marker=resp.marker
      break if resp.marker == nil
    end
    users.each do |u|
      mfa=iam.list_mfa_devices(user_name: u.user_name)[0]
      if not $quiet
        opfile.print("\"#{$profile}\",\"User\",\"None\",\"#{u.user_id}\",\"#{u.user_name}\",\"#{u.password_last_used}\",\"#{mfa[0] == nil ? 'no' : 'yes'}\"\n")
      end
      $user_count+=1
    end
  rescue Aws::IAM::Errors::AccessDenied => err
    err_msg("Insufficient permissions failure for profile #{$profile} - (#{err}) \n")
    if $continue_on_permissions_error
      return 
    else
      err_msg("exiting\n")
      exit(E_AUTH_FAILURE)
    end
  end
end

def limits(region)
  debug_msg("Getting Limits for account info for \"#{$profile}\"")
  #EC2/VPC Limits:
  client=Aws::EC2::Client.new(region: region, credentials: $credentials)
  attributes=client.describe_account_attributes().account_attributes
  max_inst=0
  max_eips=0
  sgs_per_if=0
  max_lbs=0
  max_listeners=0
  if $audit_mode
    opfile=File.open("#{$audit_dir}/#{region}/limits","w")
  else
    opfile=$stdout
  end

  opfile.print("\"#{$profile}\",\"Limits\",\"#{region}\"")
  opfile.print(",\"EC2\"")
  attributes.each do |a|
    opfile.print(",\"#{a.attribute_name}:#{a.attribute_values[0].attribute_value}\"")
  end

  # ELB Limits:
  opfile.print(",\"ELB\"")
  client=Aws::ElasticLoadBalancing::Client.new(region: region, credentials: $credentials)
  begin
    client.describe_account_limits.limits.each do |l|
      if l.name != "supported-platforms"
        opfile.print(",\"#{l.name}:#{l[:max]}\"")
      end
    end
  rescue => err
    err_msg("You need to upgrade your aws-sdk gem to support load-balancer limits")
  end


  # RDS Limits:
  opfile.print(",\"RDS\"")
  client=Aws::RDS::Client.new(region: region, credentials: $credentials)
  rds_limits=client.describe_account_attributes()
  rds_limits.account_quotas.each do |l|
    opfile.print(",\"#{l.account_quota_name}:#{l.max}\"")
  end

  # Lambdas:
  begin
    lambda = Aws::Lambda::Client.new(region: region, credentials: $credentials)
    opfile.print(",\"LAMBDA\"")
    resp=lambda.get_account_settings.account_limit
    opfile.print ("\n*** #{resp} ***\n")

    resp.each do |l|
      opfile.print(",\"#{l.account_limit}\"")
    end
  rescue => err
    opfile.print(",\"Not supported in region\"")
  end
  # ELB Limits:
  client=Aws::ElasticLoadBalancing::Client.new(region: region, credentials: $credentials)
  lb_limits=client.describe_account_limits
  lb_limits.limits.each do |l|
    case l.name
      when /classic-load-balancers/
        max_lbs=l[:max]
      when /classis-listeners/
        max_listeners=l[:max]
    end
  end
  opfile.print("\"#{$profile}\",\"Limits\",\"#{region}\",\"#{max_inst}\",\"#{max_eips}\",\"#{sgs_per_if}\",\"#{max_lbs},\",\"#{max_listeners}\"\n")
  opfile.print("\n")
end

def get_account_id(region)
  debug_msg("Getting account info for \"#{$profile}\" with credentials \"#{$credentials}")
  begin
    sts = Aws::STS::Client.new(region: region, credentials: $credentials)
    my_id= sts.get_caller_identity().account
  rescue
    raise
  end
  return my_id
end

def display_totals()
  print("Totals:\n")
  print("VPCs: #{$vpc_count}\n")                      if $show_all or $show_vpcs
  print("Running Instances: #{$running_i_count}\n")   if $show_all or $show_instances
  print("Stopped Instances: #{$stopped_i_count}\n")   if $show_all or $show_instances
  print("AMIs: #{$ami_count}\n")                      if $show_all or $show_amis
  print("Volumes: #{$volume_count}\n")                if $show_all or $show_volumes 
  print("NAT Gateways: #{$gateway_count}\n")          if $show_all or $show_nats 
  print("Internet Gateways: #{$gateway_count}\n")     if $show_all or $show_igws 
  print("Route Tables: #{$route_table_count}\n")      if $show_all or $show_routes 
  print("Snapshots: #{$snap_count}\n")                if $show_all or $show_snapshots 
  print("RDS instances: #{$rds_count}\n")             if $show_all or $show_rds 
  print("Load Balancers: #{$lb_count}\n")             if $show_all or $show_loadbalancers
  print("Elastic IPs: #{$eip_count}\n")               if $show_all or $show_eip
  print("Elastic Filesystems #{$efs_count}\n")        if $show_all or $show_efs
  print("Elasticache(s)  #{$elasticache_count}\n")    if $show_all or $show_elasticache
  print("Redshift Clusters #{$redshift_count}\n")     if $show_all or $show_redshift
  print("Key pairs #{$key_count}\n")                  if $show_all or $show_keys
  print("Users  #{$user_count}\n")                    if $show_all or $show_users
  print("Security Groups #{$security_group_count}\n") if $show_all or $show_security_groups
  print("NACLS #{$nacl_count}\n")                     if $show_all or $show_nacls
  print("Subnets  #{$subnet_count}\n")                if $show_all or $show_subnets
  print("S3 Buckets #{$bucket_count}\n")              if $show_all or $show_buckets
end

def process_command_line(argv)
  $verbose=false
  $show_all=true
  $show_instances=false
  $show_vpcs=false
  $show_subnets=false
  $debug=false
  $profile="default"
  $credentials=""
  $summarize=false
  $continue_on_permissions_error=false
  $s3_details=false
  $print_tags=false
  $pricing=false
  $audit_mode=false

  if argv.include?('-d')
    $debug=true
  end

  argv.reverse!
  until argv.empty? do
    arg=argv.pop
    case arg
      when '-a', /\-?-all/
        $show_all=true

      when /\-?-ami(s)?/
        $show_all=false
        $show_amis=true

      when '-d', /\-?-debug/
        $continue_on_permissions_error=true
        $debug=true

      when /\-?-limit(s)?/
        $show_all=false
        $show_limits=true

      when '-i', /\-?-instances/
        debug_msg("showing instances")
        $show_all=false
        $show_instances=true

      when /\-?-igw[s]?/
        $show_all=false
        $show_igws=true

      when '-l', /\-?-lb/, /\-?-loadbalancer/, /\-?-elb/
        $show_all=false
        $show_loadbalancers=true

      when '-n', /\-?-nats/
        $show_all=false
        $show_nats=true

      when /\-?-pric(ing)|(ce)|(ces)/
        debug_msg("Pricing info will be displayed")
        # Only require the module if we're doing pricing - makes the program more portable
        begin
          require 'awscosts'
        rescue =>err
          err_msg "You need the aws costs library installed - in the meantime, try running without pricing info."
        end
        $pricing=true

      when '-p', /\-?-profile/
        debug_msg("Profile #{$profile} set")
        $profile=argv.pop

      when /^-p[a-zA-z1-9\-]+.*$/
        $profile=arg[2..-1]
        debug_msg("Profile #{$profile} set")

      when /-q/, /\-?-quiet/
        debug_msg("Quiet mode enabled")
        $quiet=true

      when /\-?-nacl[s]?/
        $show_all=false
        $show_nacls=true

      when /\-?-route.*/
        $show_all=false
        $show_routes=true

      when '-r', /\-?-rds/
        $show_all=false
        $show_rds=true

      when '-t', /\-?-tags?/
        $print_tags=true

      when /\-?-key[s]?/
        $show_all=false
        $show_keys=true

      when /\-?-region/
        $regions=[ argv.pop() ]

      when /\-?-regions=/
        print("Not yet implemented\n")
        exit(1)

      when /\-?-subnet[s]?/
        $show_all=false
        $show_subnets=true

      when /\-?-snapshot[s]?/
        $show_all=false
        $show_snapshots=true

      when '-3', /\-?-s3$/
        $show_all=false
        $show_s3=true

      when '-3l', /\-?-s3l/
        $show_all=false
        $s3_details=true
        $show_s3=true

      when '-v', /\-?-volumes/, /\-?-ebs/
        $show_all=false
        $show_volumes=true

      when '-eip', /\-?-eip/
        $show_all=false
        $show_eip=true

      when /\-?-efs/
        $show_all=false
        $show_efs=true

      when /\-?-vpc[s]?/
        $show_all=false
        $show_vpcs=true
        
      when /\-?-security.*/
        $show_all=false
        $show_security_groups=true

      when /\-?-redshift/
        $show_all=false
        $show_redshift=true

      when /\-?-elasticache/
        $show_all=false
        $show_elasticache=true

      when /\-?-user[s]?/, '-u'
        $show_all=false
        $show_users=true

      when /\-?-verbose/
        $verbose=true

      when /\-?-sum(mari[sz]e)?/
        $summarize=true
        
      when /\-?-version/
        print("#{$progname} version #{$version}\n")

      when /\-?-nofail/
        $continue_on_permissions_error=true
      when /\-?-audit([-_])?(output|mode)?/
        $audit_mode=true
        $quiet=false
        time=Time.now
        run_timestamp=sprintf("%4s%02d%02d%02d%02d%02d",time.year,time.month,time.day,time.hour,time.min,time.sec)
      
      else
        print("Sorry I don't understand #{arg}")
        exit(E_USAGE)
    end
  end

  verbose_or_debug_msg "Querying AWS  using profile #{$profile}\n" 

  begin
    debug_msg("Getting credentials for profile \"#{$profile}\"")
    $credentials = Aws::SharedCredentials.new(profile_name: $profile)
  rescue => err
    err_msg("Sorry I can't find profile #{$profile} #{err}")
    exit(E_USAGE)
  end
  if $audit_mode
    begin
      require 'fileutils'
    rescue
      err_msg "Fileutils not found - unable to run in audit mode"
      exit(E_RUNTIME)
    end

    begin
      $audit_dir=sprintf("%s/%s",$profile,run_timestamp)
      FileUtils.mkdir_p($audit_dir)
      debug_msg("Created output dir #{$audit_dir} for audit mode")
    rescue
      err_msg("Unable to create output dir #{$audit_dir} for audit mode")
      exit(E_RUNTIME)
    end
  end 
end

# Use a call to Client.new to check that our credentials work
def check_creds()
  debug_msg("Checking credentials for profile \"#{$profile}\"")
  my_id=""
  begin
    sts = Aws::STS::Client.new(region: "eu-west-1", credentials: $credentials)
    my_id= sts.get_caller_identity().account
  rescue => err
    err_msg ("Unable to login using profile #{$profile}: #{err}")
    exit(E_PROFILE_ERR)
  end
end

def main(argv)
  $running_i_count=0
  $stopped_i_count=0
  $bucket_count=0
  $ami_count=0
  $snap_count=0
  $ec2_count=0
  $volume_count=0
  $vpc_count=0
  $gateway_count=0
  $rds_count=0
  $eip_count=0
  $lb_count=0
  $efs_count=0
  $elasticache_count=0
  $elasticache_snapshot_count=0
  $user_count=0
  $redshift_count=0
  $igw_count=0
  $key_count=0
  $subnet_count=0
  $security_group_count=0
  $nacl_count=0
  $route_table_count=0

  $version="1.02"
  $progname=File.basename( $PROGRAM_NAME )

  process_command_line(argv)
  check_creds()
  my_id=get_account_id($regions[0])

  $regions.each do |region|
    if $audit_mode
      begin
        FileUtils.mkdir_p("#{$audit_dir}/#{region}")
        debug_msg("created audit dir [#{$audit_dir}/#{region}]")
      rescue
        err_msg("Unable to create audit dir #{$audit_dir}/#{region} - exiting")
        exit(E_RUNTIME)
      end
      FileUtils.mkdir_p("#{$audit_dir}/all")
    end
    

    debug_msg("Region=[#{region}]")
    vpcs(region)                if $show_all or $show_vpcs

    subnets(region)             if $show_all or $show_subnets
    ec2_instances(region)       if $show_all or $show_instances
    amis(region,my_id)          if $show_all or $show_amis
    ec2_volumes(region)         if $show_all or $show_volumes 
    nat_gateways(region)        if $show_all or $show_nats 
    route_tables(region)        if $show_all or $show_routes
    internet_gateways(region)   if $show_all or $show_igws
    ec2_snapshots(region,my_id) if $show_all or $show_snapshots 
    rds_instances(region)       if $show_all or $show_rds 
    load_balancers(region)      if $show_all or $show_loadbalancers
    security_groups(region)     if $show_all or $show_security_groups
    nacls(region)               if $show_all or $show_nacls
    eips(region)                if $show_all or $show_eip
    efs(region)                 if $show_all or $show_efs
    elasticache(region)         if $show_all or $show_elasticache
    redshift(region)            if $show_all or $show_redshift
    keys(region)                if $show_all or $show_keys
    limits(region)              if $show_all or $show_limits
  end
  # Non-regional stuff:
  s3_info()        if $show_all or $show_s3
  users()          if $show_all or $show_users

  display_totals if $summarize
end

begin
  main(ARGV)
rescue Interrupt
  warn "\nAborted at user request"
  exit ABORTED
end
