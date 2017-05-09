# aws_info
ruby version of the aws cli uses awscosts gem to get costing.   

aws_info essentially duplicates the functions available from the 
aws cli, but with a couple of caveats:
1.  All regions are queried by default
2.  All assets are queried by default
3.  Costs are added to output

So, this command for example:

aws_info -prock -t -price

would attempt to describe all assets owned by the account described in 
the "rock" profile, in all regions, where possible printing all tags
(the -t option), and again where possible, list pricing info for each
asset.


