#!/usr/bin/perl


use Date::Calc qw(Today_and_Now);
use LWP::UserAgent;
use File::Copy;
use Sys::Hostname;
use Cwd;

$mypath = cwd();
$logfile = "$mypath/check.log";
$outdir = "$mypath/configs";

$dekey = "0643253d8a770fc1f6f7127eae635c1c";


%ifmap = (
    "2800" => {
	lo => "Loopback0",
	wan => "GigabitEthernet0/0",
	lan => "GigabitEthernet0/1",
	coloup => "GigabitEthernet0/3/0",
	colodown => "GigabitEthernet0/3/0"
    },
    "C2900" => {
	lo => "Loopback0",
	wan => "GigabitEthernet0/2",
	lan => "GigabitEthernet0/0",
	coloup => "GigabitEthernet0/1",
	colodown => "GigabitEthernet0/1"
    },
    "C3900e" => {
	lo => "Loopback0",
	wan => "GigabitEthernet0/2",
	lan => "GigabitEthernet0/0",
	coloup => "GigabitEthernet0/1",
	colodown => "GigabitEthernet0/1"
    },
    "ISR" => {
	lo => "Loopback0",
	wan => "GigabitEthernet0/0/0",
	lan => "GigabitEthernet0/0/1",
	coloup => "GigabitEthernet0/0/2",
	colodown => "GigabitEthernet0/0/0",
    },
);


$routername = "";
if ( defined ( $ARGV[0] ) ) {
	$routername = $ARGV[0];
}

if ( $routername eq "?" or $routername eq "-?" or $routername eq "-h") {
	print "Usage: perl wan-check.pl <routername>\n";
	print "For example: perl wan-check.pl <routername>\n";
	print "# This script is to be run as required to check the consistency of configuration after remote router platform upgrade\n";
	print "# with the latest known configuration of the old platform.\n";
	print "# This script is part of a two-script bundle which does the following:\n";
	print "###\n";
	print "# Collect script (the other script) refreshes the configuration file in 'configs' folder for a list of routers in 'routers.txt' file from Device Expert\n";
	print "# as long as the router is 2800 or 3800 series router\n";
	print "###\n";
	print "# Check script (this script), when called against a router name:\n";
	print "# - retrieves latest config from Device Expert\n";
	print "# - checks if the router is a new model\n";
	print "# - if so, then checks if the configuration on the new model is consistent with the old 2800/3800 model and alerts if different.\n";
	print "# Three things to check:\n";
	print "# ET4L - IP on loopback interface\n";
	print "# BW upgrade - check policy on the WAN interface\n";
	print "# subnet expansion - check that routes and interface masks are the same\n";
	exit;
}

my @log;		# collect error messages

my %configverions;	# contains current config versions for routers
my %upgradedlist;	# list of already upgraded routers
my %nochangelist;	# list of routers with no config changes

my @routerparts;	# explode of JSON response

my @oldconfiglines;
my @newconfiglines;
my $oldconfig;
my $newconfig;

my $oldmodel;
my $newmodel;

my $content;		# content of HTTP response

my $lastversion;	# latest version of the configuration file

($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
$starttime = "$year-$month-$day-$hour:$min:$sec";
$host = hostname();

open LOG, ">>", $logfile;
print LOG "Generated on $starttime\n";

$keepgoing = 1;

$ua = LWP::UserAgent->new;
$deurl = "https://deviceexpert.nms.det.nsw.edu.au:6060/api";

## Get router IP

my @addrs = nslookup $routername.".net.det.nsw.edu.au";
$routerip = $addrs[0];
if ( $routerip eq "" )
{
	$error = "IP ddress of the router $routername.net.det.nsw.edu.au can not be resolved\n";
	print LOG $error;
	push ( @log, $error );	
	$keepgoing = 0;
}

if ( $keepgoing )
{
	## Get the device details
	$derequest="{API_KEY:".$dekey.",IPADDRESS:$routerip,ACTION:GET_DEVICE}";
	$req = HTTP::Request->new( 'POST', $deurl );
	$req->header( 'Content-Type' => 'application/json' );
	$req->content( $derequest );
	$response = $ua->request( $req );
	$content = $response->content();

	if ( $content eq "")
	{
		$error = "$routername ($routerip): Failed to get device details from Device Expert\n";
		print LOG $error;
		$keepgoing = 0;
	}
}

if ( $keepgoing )
{
	## Check the platform
	$platform = "";
	@routerparts = split ("\",\"", $content);
	foreach $routerpart (@routerparts)
	{
		if ( $routerpart =~ /^SERIES\":\"(.*)/ )
		{
			$newmodel = $1;
		}
	}

	if ( $newmodel eq "2800" )
	{
		$error = "$routername ($routerip): Device Expert still has old platform\n";
		print LOG $error;
		$keepgoing = 0;
	}
}
	
if ( $keepgoing )
{
	## $cfgfile = "$outdir\\$routername.cfg";
	open ROUTERS, "<", $outdir."\\".$routername.".cfg" or die "Could not open file $outdir/$routername.cfg";
	@oldconfiglines = readline (ROUTERS);
	close ROUTERS;
	$oldmodel = "2800";

	## Get Startup config
	$derequest="{API_KEY:".$dekey.",IPADDRESS:$routerip,ACTION:GET_CONFIGURATION}";
	$req = HTTP::Request->new( 'POST', $deurl );
	$req->header( 'Content-Type' => 'application/json' );
	$req->content( $derequest );
	$response = $ua->request( $req );
	$content = $response->content();

	if ( $content eq "")
	{
		$error = "$routername ($routerip): Failed to get device configuration from Device Expert\n";
		print LOG $error;
		$keepgoing = 0;
	}
}

if ( $keepgoing )
{
	@routerparts = split ("\",\"", $content);

	$startup = "";

	foreach $routerpart (@routerparts) {
		if ( $routerpart =~ /^STARTUP\":\"(.*)/ ) {
			$newconfig = $1;
		}
	}

	if ( $newconfig eq "") {
		print "Failed to identify running configuration for router $routername\n";
		print LOG "Failed to identify running configuration for router $routername\n";
		$keepgoing = 0;
	}
}

if ( $keepgoing )
{

	my @oldroutes;		# list of device routes
	my %oldifsummary;		# hash of interface parameters (name, type, description, IP)
	my %oldiflist;		# hash (device interfaces: lo, wan, lan, other1 etc) of %ifsummary hashes

	my @newroutes;		# list of device routes
	my %newifsummary;	# hash of interface parameters (name, type, description, IP)
	my %newiflist;		# hash (device interfaces: lo, wan, lan, other1 etc) of %ifsummary hashes

	## Parse old config
	
	@oldroutes = ();
	%oldiflist = {};
	$oldbandwidth = "";
	$isinterface = 0;
	$isrouting = 0;
	$model = $oldmodel;

	foreach $line (@oldconfiglines) {
		chomp $line;
		if ( $line =~ /^interface (.*)/  )
		{
			###### Interface processing
			$isinterface = 1;
			$ifname = $1;
			$ipaddress = "";
			@interface = ();
			%ifsummary = {};
			$ifsummary{"name"} = $1;

			$iftype = "";
			$from = $ifmap{$model};
			for $key ( keys %{$from} )
			{
				if ( $ifname eq $ifmap{$model}{ $key } )
				{
					$iftype = $key;
				}
			}

			if ("" eq $iftype and $ifname ne "Embedded-Service-Engine0/0") {
				print "Unknown purpose for interface $ifname in router $routername\n";
				print LOG "Unknown purpose for interface $ifname in router $routername\n";
			}

			$ifsummary{"type"} = $iftype;
			$ifsummary{"old"} = $1;
		} elsif ( $line =~ /^ description (.*)/  ) {
			$description = $1;
			$ifsummary{"description"} = $1;
			if ( $line =~ /downstream/i  ) {
				$iftype = "colodown";
			} elsif ( $line =~ /upstream/i  ) {
				$iftype = "coloup";
			}
			$ifsummary{"type"} = $iftype;

		} elsif ( $line =~ /^ ip address (.*)/  ) {
			if ( $ipaddress ne "" ) { $ipaddress = $ipaddress."#"; }
			$ipaddress = $ipaddress.$1;
			$ifsummary {"ip"} = $ipaddress;
		} elsif ( $line =~ /^ bandwidth (.*)000$/  ) {
			$oldbandwidth = $1;
		###### IP Route processing
		} elsif ( $line =~ /^ip route (.*)/  ) {
			push ( @oldroutes, $line );
		######  Section closing processing
		} elsif ($line eq "!") {
			if ($isinterface) {
				$isinterface = 0;

				$type = $ifsummary {"type"};
				if ( "" ne $type) {
					$oldiflist{$type} = {};
					for $key ( keys %ifsummary ) {
					     $oldiflist{$type}{$key} = $ifsummary{$key};
					}
				}
			}
		}
	}

	## Parse new config
	@newconfiglines = split ("\\\\n", $newconfig);
	
	@newroutes = ();
	%newiflist = {};
	$newbandwidth = "";
	$isinterface = 0;
	$isrouting = 0;
	$model = $newmodel;

	foreach $line (@newconfiglines) {
		if ( $line =~ /^interface (.*)/  )
		{
			###### Interface processing
			$isinterface = 1;
			$ifname = $1;
			$ipaddress = "";
			@interface = ();
			%ifsummary = {};
			$ifsummary{"name"} = $1;

			$iftype = "";
			$from = $ifmap{$model};
			for $key ( keys %{$from} )
			{
				if ( $ifname eq $ifmap{$model}{ $key } )
				{
					$iftype = $key;
				}
			}

			if ("" eq $iftype and $ifname ne "Embedded-Service-Engine0/0") {
				print "Unknown purpose for interface $ifname in router $routername\n";
				print LOG "Unknown purpose for interface $ifname in router $routername\n";
			}

			$ifsummary{"type"} = $iftype;
			$ifsummary{"old"} = $1;
		} elsif ( $line =~ /^ description (.*)/  ) {
			$description = $1;
			$ifsummary{"description"} = $1;
			if ( $line =~ /downstream/i  ) {
				$iftype = "colodown";
			} elsif ( $line =~ /upstream/i  ) {
				$iftype = "coloup";
			}
			$ifsummary{"type"} = $iftype;

		} elsif ( $line =~ /^ ip address (.*)/  ) {
			if ( $ipaddress ne "" ) { $ipaddress = $ipaddress."#"; }
			$ipaddress = $ipaddress.$1;
			$ifsummary {"ip"} = $ipaddress;
		} elsif ( $line =~ /^ bandwidth (.*)000$/  ) {
			$newbandwidth = $1;
		###### IP Route processing
		} elsif ( $line =~ /^ip route (.*)/  ) {
			push ( @newroutes, $line );
		######  Section closing processing
		} elsif ($line eq "!") {
			if ($isinterface) {
				$isinterface = 0;

				$type = $ifsummary {"type"};
				if ( "" ne $type) {
					$newiflist{$type} = {};
					for $key ( keys %ifsummary ) {
					     $newiflist{$type}{$key} = $ifsummary{$key};
					}
				}
			}
		}
	}
	
	## Compare items
	$inconsistent = 0;
	
	if ( $oldbandwidth ne $newbandwidth )
	{
		print "$routername ($routerip): Bandwith is different in the old model and new model - Bandwidth upgrade project ???\n";
		print LOG "$routername ($routerip): Bandwith is different in the old model and new model - Bandwidth upgrade project ???\n";
		$inconsistent = 1;
	}
	
	if ( $oldiflist{"lo"}{"ip"} ne $newiflist{"lo"}{"ip"} )
	{
		print "$routername ($routerip): Different IP addresses on Loopback interface - ET4L project ???\n";
		print LOG "$routername ($routerip): Different IP addresses on Loopback interface - ET4L project ???\n";
	}
	
	foreach $oldroute ( @oldroutes)
	{
		$found=0;
		foreach $newroute ( @newroutes)
		{
			if ( $newroute eq $oldroute )
			{
				$found = 1;
			}
		}
		if ($found == 0)
		{
			print "$routername ($routerip): Route is missing on new model ( $oldroute) - Subnet expansion project ???\n";
			print LOG "$routername ($routerip): Route is missing on new model ( $oldroute) - Subnet expansion project ???\n";
			$inconsistent = 1;
		}
	}
	
	for $iftype ( keys %newiflist )
	{
		$newip = $newiflist{$iftype}{"ip"};
		@newips = split ("#", $newip);

		$oldip = $oldiflist{$iftype}{"ip"};
		@oldips = split ("#", $oldip);
	     
		foreach $oldip ( @oldips)
		{
			$found=0;
			foreach $newip ( @newips)
			{
				if ( $newip eq $oldip )
				{
					$found = 1;
				}
			}
			if ($found == 0)
			{
				print "$routername ($routerip): IP address is missing on new model ( $oldip ) - Subnet expansion project?\n";
				print LOG "$routername ($routerip): IP address is missing on new model ( $oldip ) - Subnet expansion project?\n";
				$inconsistent = 1;
			}
		}
	}
	if ($inconsistent)
	{
		print "$routername ($routerip): configuration inconsistencies have been found, please see above messages\n";
		print LOG "$routername ($routerip): configuration inconsistencies have been found, please see above messages\n";
	}
	else
	{
		print "$routername ($routerip): No configuration inconsistencies have been found\n";
		print LOG "$routername ($routerip): No configuration inconsistencies have been found\n";
	}
}