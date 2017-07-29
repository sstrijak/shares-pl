#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use File::Copy;
use File::Basename;
use DBI;
use GD::Graph::lines;
use GD::Graph::bars;
use GD::Graph::Data;

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $otomessage = "";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "stocks";

# Flow control and reporting
my $keepgoing = 1;

# Script data

my $date = "";
my $code = "";

my @xaoclose;
my $xaodate;

my @dates;
my %alldates;
my %alldata;
my @allcodes;
my $dateis = "";
my $codeis = "";

my $zero = "0" ;

my $graph;
my @data;
my @graphlegend;

open LOG, ">>", $logfile;

########## Read parameters and display help message
my $graphcode = "";
if ( defined ( $ARGV[0] ) ) { $graphcode = $ARGV[0]; }
my $graphstart = "";
if ( defined ( $ARGV[1] ) ) { $graphstart = $ARGV[1]; }
my $graphend = "";
if ( defined ( $ARGV[2] ) ) { $graphend = $ARGV[2]; }
my $graphtype = "lines";
if ( defined ( $ARGV[3] ) ) { $graphtype = $ARGV[3]; }
my $graphdata = "pcnt";
if ( defined ( $ARGV[4] ) ) { $graphdata = $ARGV[4]; }

if ( $graphcode eq "" or $graphcode eq "?" or $graphcode eq "-?" or $graphcode eq "-h") {
	print "Usage: perl graph.pl {code|code,code} [<start yyyy-mm-dd>] [<end yyyy-mm-dd>] [lines|bars] [pcnt|daypcnt]\n";
	exit;
}

####### open database
my $dsn = "DBI:mysql:database=$dbname;host=$dbhost;port=$dbport";
my $dbh = DBI->connect($dsn, $dbuser, $dbpassword);
my $error = $dbh->{'mysql_error'};

if ( $error)
{
	$thismessage = "Error connecting to database: $error";
	logentry ( $thismessage );
	$message .= "$thismessage\n";
	$keepgoing = 0;
}

if ($keepgoing)
{
	## identify date range
	if ( $graphstart )
	{
		$dateis = "date >= '$graphstart' and date <= '$graphend' ";
	}
	
	## set of codes 
	@allcodes = split (',', $graphcode ); 
	$codeis = "(code='".$allcodes[0]."'";
	for ( my $i = 1; $i < scalar @allcodes; $i ++ ) { $codeis .= " or code='".$allcodes[$i]."'"; }
	$codeis .= ")";

	## get dates
	$sql = "select distinct date from daily where $dateis and $codeis order by date asc";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$datecount = 0 ;
	
	while (@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		if ( $datecount )	{ $graphend =  $date ; }
		else			{ $graphstart =  $date ; }
		$alldates{$date} = $datecount++;
		# push @dates, $date ;
		$arraysize = scalar @dates ;
		$dates[ $arraysize ] = $date;
	}
	$sth->finish();
	$dateis = "date >= '$graphstart' and date <= '$graphend' ";

	$pcnt = 0 ;
	if ( $graphdata eq "pcnt" ) { $pcnt = 1 ; }

	foreach $code ( @allcodes )
	{
		$alldata { $code } = [];
		$codedates { $code } = {};
		$codeclose { $code } = [];

		$sql = "select date, close from daily where code='$code'";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		$datecount = 0;
		while (@row = $sth->fetchrow_array())
		{
			$date = $row[0];
			$close = $row[1];
			$codedates { $code } { $date } = $datecount++;
			# push $codeclose { $code }, $close ;
			$arraysize = scalar @ { $codeclose { $code } } ;
			$codeclose { $code } [ $arraysize ] = $close;

		}		
		$sth->finish();
		
		$startclose = 0;
		$lastclose = 0;
		
		foreach $date ( sort keys %alldates )
		{
			$codedata = 0; 
			if ( defined ( $codedates { $code } { $date } ) ) {
				$thisdateindex = $codedates { $code } { $date };
				if  ( $thisdateindex > 0 )
				{
					if ( !$startclose ) { $startclose = $codeclose { $code } [ $thisdateindex - 1 ] ; }
					$lastclose = $codeclose { $code }[ $thisdateindex - 1 ] ;
					$close = $codeclose { $code }[ $thisdateindex ] ;
					
					if ( $pcnt )
					{
						if ( $startclose )
						{
							$codedata = ( $close - $startclose ) / $startclose * 100;
						}
					} else
					{
						if ( $lastclose )
						{
							$codedata = ( $close - $lastclose ) / $lastclose * 100;
						}
					}
				}
				else { }
			}
			#push $alldata { $code }, $codedata ;
			$arraysize = scalar @ { $alldata { $code } } ;
			$alldata { $code }[ $arraysize ] = $codedata;
		}
	}

	push @data, \@dates;


	if ( $graphtype eq "lines" )	{ $graph = new GD::Graph::lines(1600, 800); }
	else 				{ $graph = new GD::Graph::bars(1600, 800); }

	foreach $code ( sort keys %alldata )
	{
		if ( defined $alldata { $code } )
		{
			#push @data, $alldata { $code } ;
			$arraysize = scalar @data ;
			$data [ $arraysize ] = $alldata { $code } ;
		} ;
		
		if ( defined ( $code ) )
		{
			#push @graphlegend, $code ;
			$arraysize = scalar @graphlegend ;
			$graphlegend [ $arraysize ] = $code;
		} ;
	}

	$graph->set_legend( @graphlegend );

	$graph->set( 
		x_labels_vertical => 1,
		x_label           => 'Trade Date',
		y_label           => '%',
		line_width	  => 3,
		bargroup_spacing  => 10,
#		title             => "$code performance compared to market",
		transparent       => 0,
#		fgclr             => [qw(black)],
		y_number_format   => '%0.2f',
#			x_label_skip      => 5,
		long_ticks        => 1,
	) or warn $graph->error;

	$graph->set_title_font(GD::gdGiantFont);
	$graph->set_legend_font(GD::gdGiantFont);
	$graph->set_x_label_font(GD::gdGiantFont);
	$graph->set_y_label_font(GD::gdGiantFont);
	$graph->set_x_axis_font(GD::gdGiantFont);
	$graph->set_y_axis_font(GD::gdGiantFont);
	$graph->set_values_font(GD::gdGiantFont);
        
	$graph->plot(\@data) or die $graph->error;

	my $file = "$graphcode#$graphstart#$graphend.png";
	open(my $out, '>', $file) or die "Cannot open '$file' for write: $!";
	binmode $out;
	print $out $graph->gd->png;
	close $out;
}

# closing
close LOG;

sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

