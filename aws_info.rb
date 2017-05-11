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
  $stderr.print("DEBUG ") if $debug
  if $verbose or $debug
    words.each do |word|
      $stderr.print("#{word} ")
    end
    $stderr.print("\n")
  end
  $stderr.flush()
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

def vpcs(region)
  ec2 = Aws::EC2::Client.new(region: region,credentials: $credentials)
  ec2.describe_vpcs.each do |v|
    v.vpcs.each do |vpc|
    print("\"#{$profile}\",\"VPC:\",\"#{region}\",\"#{vpc.vpc_id}\",\"#{vpc.cidr_block}\"")
    if $print_tags
      vpc.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
        print(",\"#{tag.key}:#{tag.value}\"")
      end
    end
    print("\n")
    end
  end
end
def keys(region)
  verbose_or_debug_msg("Checking keys in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Client.new(region: region,credentials: $credentials)
  ec2.describe_key_pairs.each do |k|
    if not $quiet
      k.key_pairs.each do |k|
        print("\"#{$profile}\",\"Key Pair\",\"#{region}\",\"#{k.key_name}\",\"#{k.key_fingerprint}\"\n")
      end
    end
    $key_count+=1
  end
end

#EC2 Instances
def ec2_instances(region)
  verbose_or_debug_msg("Checking running instances in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Resource.new(region: region,credentials: $credentials)
  if $pricing
    verbose_or_debug_msg("Gathering instance pricing info for region #{region}")
    price_region = AWSCosts.region(region)
    if price_region != NIL
      prices=price_region.ec2.on_demand(:linux).price
    end
  end
  begin
    ec2.instances.each do |i|
      if i.state.name == "running"
        if not $quiet
          print "\"#{$profile}\",\"Instance:\",\"#{region}\",\"#{i.id}\",\"#{i.instance_type}\",\"#{i.image_id}\",\"#{i.vpc_id}\""
          if $pricing 
            if price_region == NIL
              print(",\"\"")
            else
              print(",\"#{prices[i.instance_type]}\"")
            end
          end
          if $print_tags
            i.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
              print(",\"#{tag.key}:#{tag.value}\"")
            end
          end
          print("\n")
        end
      end
    end
  rescue Aws::EC2::Errors::AuthFailure =>err
    err_msg("Authentication failure for profile #{$profile} - (#{err}) - exiting\n")
    exit(E_AUTH_FAILURE)
  end
  $instance_count+=1
end

# EBS:
def ec2_volumes(region)
  verbose_or_debug_msg("Checking EC2 volumes in region #{region} for profile #{$profile}")
  ec2 = Aws::EC2::Resource.new(region: region, credentials: $credentials)
  if $pricing
    verbose_or_debug_msg("Gathering EBS pricing info for region #{region}")
    price_region=AWSCosts.region(region)
    if price_region != NIL
      prices=price_region.ec2.ebs.price
      print prices
    end
  end
  ec2.volumes.each do |v|
    if v.state !~ /delet/
      if not $quiet
        printf("\"#{$profile}\",\"Volume:\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"" ,region,v.id,v.size,v.volume_type,v.state)
        
        #if $pricing
          print("Price info\n")
          #if prices == NIL or not prices.has_key?(v.volume_type)
            #price_region.each do |p|
              #print("price for #{p.name}, = #{p.values.prices}\n")
            #end
          #end
        #end
        if $print_tags
          v.tags.sort_by { |hsh| hsh[:key] }.each do |tag|
            print("\",\"#{tag.key}:#{tag.value}\"")
          end
        end
        print("\n")
      end
      $volume_count+=1
    end
  end
end

def ec2_snapshots(region,my_id)
  verbose_or_debug_msg("Checking snapshots in region \"#{region} owned by account id \"#{my_id}\"")
  ec2 = Aws::EC2::Resource.new(region: region, credentials: $credentials)
  snapshots=ec2.snapshots({filters: [{name: "owner-id", values: [ my_id ]}]})
  snapshots.each do |s|
    if not $quiet
      printf("\"#{$profile}\",\"Snapshot:\",\"%s\",\"%s\",\"%s\",\"%s\"" ,region,s.id,s.volume_size,s.start_time.to_s)
      if $print_tags
        s.tags.each do |tag|
          print("\",\"#{tag.key}:#{tag.value}\"")
        end
      end
      print("\n")
    end
    $snap_count+=1
  end
end

def security_groups(region)
  verbose_or_debug_msg("Checking Security Groups in region \"#{region}\n")
  ec2 = Aws::EC2::Resource.new(region: region, credentials: $credentials)
  groups=ec2.snapshots
  groups.each do |s|
    if not $quiet
      printf("\"#{$profile}\",\"Snapshot:\",\"%s\",\"%s\",\"%s\",\"%s\"" ,region,s.id,s.volume_size,s.start_time.to_s)
      if $print_tags
        s.tags.each do |tag|
          print("\",\"#{tag.key}:#{tag.value}\"")
        end
      end
      print("\n")
    end
    $snap_count+=1
  end
end

def rds_instances(region)
  verbose_or_debug_msg("Checking RDS instances in region \"#{region}\" for profile \"#{$profile}\"")
  rds = Aws::RDS::Resource.new(region: region, credentials: $credentials)
  begin
    rds.db_instances.each do |r|
      if not $quiet
        #printf("\"#{$profile}\",\"Database:\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"" ,region,r.id,r.db_name,r.db_instance_class,r.engine)
        print("\"#{$profile}\",\"Database:\",\"#{region}\",\"#{r.id}\",\"#{r.db_name}\",\"#{r.db_instance_class}\",\"#{r.engine}\",\"#{r.db_subnet_group.vpc_id}\"")
        # Hmmm.  Possibly not yet supported
        #if $print_tags
          #r.tags.each do |tag|
            #print("\",\"#{tag.key}:#{tag.value}\"")
          #end
        #end
        print("\n")
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

  result = ec2.describe_internet_gateways()
  result.internet_gateways.each do |gw|
    if not $quiet
      print("\"#{$profile}\",\"Internet Gateway:\",\"#{region}\",\"#{gw.internet_gateway_id}\"")
      gw.attachments.each do |a|
        print(",\"#{a.vpc_id}\"")
      end
      if $print_tags
        gw.tags.each do |tag|
          print("\",\"#{tag.key}:#{tag.value}\"")
        end
      end
      print("\n")
    end
    $igw_count+=1
  end
end

# Nat gateways don't currently support tags
def nat_gateways(region)
  verbose_or_debug_msg("Checking NAT gateways in region \"#{region}\" for profile \"#{$profile}\"")
  ec2 = Aws::EC2::Client.new(region: region, credentials: $credentials)

  loop do 
    result = ec2.describe_nat_gateways()
    result.nat_gateways.each do |gw|
      if not $quiet
        print "\"#{$profile}\",\"NAT Gateway:\",\"#{region}\",\"#{gw.vpc_id}\",\"#{gw.nat_gateway_id}\",\"#{gw.subnet_id}\"\n"
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

  result = ec2.describe_addresses()
  result.addresses.each do |add|
    if not $quiet
      print "\"#{$profile}\",\"EIP\",\"#{region}\",\"#{add.public_ip}\",\"#{add.association_id or 'None'}\"\n"
    end
    $eip_count+=1
  end
end

def load_balancers(region)
  verbose_or_debug_msg("Checking Load Balancers in region \"#{region}\" for profile \"#{$profile}\"")
  client = Aws::ElasticLoadBalancing::Client.new(region: region, credentials: $credentials)
  lbs=client.describe_load_balancers()
  lbs.load_balancer_descriptions.each do |lb_desc|
    if not $quiet
      print "\"#{$profile}\",\"Load Balancer:\",\"#{region}\",\"#{lb_desc.vpc_id}\",\"#{lb_desc.load_balancer_name}\",\"#{lb_desc.scheme}\""
      # TODO:
      #if $print_tags
        #lb_desc.tags.each do |tag|
          #print("\",\"#{tag.key}:#{tag.value}\"")
        #end
      #end
      print("\n")
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
  
  # If we've not specified details, then simply list the buckets and return.
  if ! $s3_details
    s3_resource.buckets.each do |b|
      print("\"#{$profile}\",\"S3 Bucket\",\"All\",\"#{b.name}\",\"#{b.creation_date}\"\n")
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
        print("\"#{$profile}\",\"s3 bucket\",\"#{region}\",\"#{bucket.name}\",\"#{total_size}\"\n")
        all_buckets[bucket.name]=true
      end
    rescue Aws::S3::Errors::ServiceError => err
      debug_msg("#{err.inspect()}\n")
    end
  end
end

def efs(region)
  verbose_or_debug_msg("Checking EFS resources in region #{region} for profile \"#{$profile}\"")
  efs = Aws::EFS::Client.new(region: region, credentials: $credentials)
  begin # EFS Not supported in all regions, so wrap in exception handling to deal with TCP connection failures
    efs.describe_file_systems.file_systems.each do |fs|
      if not $quiet
        print("\"#{$profile}\",\"EFS\",\"#{region}\",\"#{fs.creation_token}\",\"#{fs.file_system_id}\",\"#{fs.size_in_bytes['value']}\"")
        if $print_tags
          fs.tags.each do |tag|
            print("\",\"#{tag.key}:#{tag.value}\"")
          end
        end
        print("\n")
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
  begin
    elasticache = Aws::ElastiCache::Client.new(region: region, credentials: $credentials)
    clusters = elasticache.describe_cache_clusters()
    clusters.cache_clusters.each do |c|
      if not $quiet
        print("\"Elasticache Cluster\",\"#{region}\",\"#{c.cache_cluster_id}\",\"#{c.cache_node_type}\",\"#{c.engine}\"\n")
      end
      $elasticache_count+=1
    end
    snapshots=elasticache.describe_snapshots()
    snapshots.each do |ss|
      if not $quiet
        if ss.snapshots.length != 0
          print("\"#{$profile}\",\"Elasticache snapshot\",\"#{ss}\"\n") 
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
    efs.describe_clusters.each do |cluster|
      cluster.clusters.each do |c|
        if not $quiet
          # using a multiline broken string to preserve indentation:
          string="\"#{$profile}\",\"#{region}\",\"Redshift Cluster\",\"#{c.cluster_identifier}\",\"#{c.cluster_status}\",\"#{c.node_type}\",\""\
          "\"#{c.number_of_nodes}\",\"#{c.vpc_id}\""
          print string
        end 
        $redshift_count+=1
      end
    end
  begin # Redshift is not supported by all regions
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
        print("\"#{$profile}\",\"User\",\"None\",\"#{u.user_id}\",\"#{u.user_name}\",\"#{u.password_last_used}\",\"#{mfa[0] == nil ? 'no' : 'yes'}\"\n")
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


def get_account_id(region)
  debug_msg("Getting account info for \"#{$profile}\" with credentials \"#{$credentials}")
  begin
    sts = Aws::STS::Client.new(region: region, credentials: $credentials)
    my_id= sts.get_caller_identity().account
    
    #my_id=sts.new.get_caller_identity.account()
  rescue
    raise
  end
  return my_id
end

def display_totals()
  print("Totals:\n")
  print("Instances: #{$instance_count}\n")         if $show_all or $show_instances
  print("Volumes: #{$volume_count}\n")             if $show_all or $show_volumes 
  print("NAT Gateways: #{$gateway_count}\n")       if $show_all or $show_nats 
  print("Internet Gateways: #{$gateway_count}\n")  if $show_all or $show_igws 
  print("Snapshots: #{$snapshot_count}\n")         if $show_all or $show_snapshots 
  print("RDS instances: #{$rds_count}\n")          if $show_all or $show_rds 
  print("Load Balancers: #{$lb_count}\n")          if $show_all or $show_loadbalancers
  print("Elastic IPs: #{$eip_count}\n")            if $show_all or $show_eip
  print("Elastic Filesystems #{$efs_count}\n")     if $show_all or $show_efs
  print("Elasticache(s)  #{$elasticache_count}\n") if $show_all or $show_elasticache
  print("Redshift Clusters #{$redshift_count}\n")  if $show_all or $show_redshift
  print("Key pairs #{$key_count}\n")               if $show_all or $show_keys
  print("Users : #{$user_count}\n")                if $show_all or $show_users
end

def process_command_line(argv)
  $verbose=false
  $show_all=true
  $show_instances=false
  $show_vpcs=false
  $debug=false
  $verbose=false
  $profile="default"
  $credentials=""
  $summarize=false
  $continue_on_permissions_error=false
  $s3_details=false
  $print_tags=false
  $pricing=false

  if argv.include?('-d')
    $debug=true
  end

  argv.reverse!
  until argv.empty? do
    arg=argv.pop
    debug_msg("process command-line : argv=[#{argv}], arg=[#{arg}]")
    case arg
      when '-a', /\-?-all/
        $show_all=true

      when '-d', /\-?-debug/
        $continue_on_permissions_error=true
        $debug=true

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
        $verbose=false
        $quiet=true

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

      when '-s', /\-?-snapshots/
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

      when /\-?-summarize/
        $summarize=true
        
      when /\-?-version/
        print("#{$progname} version #{$version}\n")

      when /\-?-nofail/
        $continue_on_permissions_error=true

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
end

# Use a call to Client.new to check that our credentials work
def check_creds()
  debug_msg("Checking credentials for profile \"#{$profile}\"")
  begin
    sts = Aws::STS::Client.new(region: "eu-west-1", credentials: $credentials)
    my_id= sts.get_caller_identity().account
  rescue => err
    err_msg ("Unable to login using profile #{$profile}: #{err}")
    exit(E_PROFILE_ERR)
  end
end

def main(argv)
  $instance_count=0
  $snap_count=0
  $ec2_count=0
  $volume_count=0
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

  $version="0.25"
  $progname=File.basename( $PROGRAM_NAME )

  process_command_line(argv)
  check_creds()
  my_id=get_account_id($regions[0])

  $regions.each do |region|
    debug_msg("Region=[#{region}]")
    vpcs(region)                if $show_all or $show_vpcs
    ec2_instances(region)       if $show_all or $show_instances
    ec2_volumes(region)         if $show_all or $show_volumes 
    nat_gateways(region)        if $show_all or $show_nats 
    internet_gateways(region)   if $show_all or $show_igws
    ec2_snapshots(region,my_id) if $show_all or $show_snapshots 
    rds_instances(region)       if $show_all or $show_rds 
    load_balancers(region)      if $show_all or $show_loadbalancers
    eips(region)                if $show_all or $show_eip
    efs(region)                 if $show_all or $show_efs
    elasticache(region)         if $show_all or $show_elasticache
    redshift(region)            if $show_all or $show_redshift
    keys(region)                if $show_all or $show_keys
  end
  # Non-regional stuff:
  s3_info()                   if $show_all or $show_s3
  users()                     if $show_all or $show_users

  display_totals if $summarize
end

begin
  main(ARGV)
rescue Interrupt
  warn "\nAborted at user request"
  exit ABORTED
end
