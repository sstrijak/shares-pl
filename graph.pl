#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
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
my $wheredateis = "";

my $zero = "0" ;

my $graph;
my @data;
my @graphlegend;

open LOG, ">>", $logfile;

########## Read parameters and display help message
my $graphtype = "lines";
if ( defined ( $ARGV[0] ) ) { $graphtype = $ARGV[0]; }
my $graphdata = "pcnt";
if ( defined ( $ARGV[1] ) ) { $graphdata = $ARGV[1]; }
my $graphstart = "";
if ( defined ( $ARGV[2] ) ) { $graphstart = $ARGV[2]; }
my $graphend = "";
if ( defined ( $ARGV[3] ) ) { $graphend = $ARGV[3]; }
my $graphcode = "";
if ( defined ( $ARGV[4] ) ) { $graphcode = $ARGV[4]; }

if ( $graphtype eq "" or $graphtype eq "?" or $graphtype eq "-?" or $graphtype eq "-h") {
	print "Usage: perl graph.pl [lines|bars] [pcnt|dapcnt] <start yyyy-mm-dd> <end yyyy-mm-dd> <code>\n";
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

	# get index data
	$sql = "select date, close from daily where code='XAO'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while ( @row = $sth->fetchrow_array() ) {
		$date = $row[0];
		$close = $row [1];
		push @xaoclose, $close;
		$xaodate {$date} = scalar @xaoclose - 1;
	}
	$sth->finish();


	## identify date range
	if ( $graphstart ) { $wheredateis = "where date >= '$graphstart' and date <= '$graphend' "; }

	## get dates
	$sql = "select distinct date from running $wheredateis order by date asc";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$datecount = 0 ;
	
	while (@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		if ( $datecount )	{ $graphend =  $date ; }
		else			{ $graphstart =  $date ; }
		$alldates{$date} = $datecount++;
		push @dates, $date ;
	}		
	$sth->finish();
	$wheredateis = "where date >= '$graphstart' and date <= '$graphend' ";
	
	if ( $graphcode ) { push @allcodes, $graphcode }
	else
	{
		$graphcode = "000" ;
		$sql = "select distinct code from running $wheredateis";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while (@row = $sth->fetchrow_array())
		{
			$code = $row[0];
			push @allcodes, $code;
		}		
		$sth->finish();
	}

	$alldata { "XAO" } = [];

	if ( $graphdata eq "pcnt" )
	{
		$select = "select date, pcnt from running " ;
		
		$xaostartindex = $xaodate { $graphstart } - 1 ; 
		$xaostartclose = $xaoclose [$xaostartindex];
		
		foreach $date ( sort keys %alldates )
		{
			$xaoindex = $xaodate { $date } ; 
			$xaoclose = $xaoclose [ $xaoindex ] ;
			$xaodata = ( $xaoclose - $xaostartclose ) / $xaostartclose * 100;
			push $alldata { "XAO" }, $xaodata ;
		}
	}
	else
	{
		$select = "select date, daypcnt from running " ;

		foreach $date ( sort keys %alldates )
		{
			$xaoindex = $xaodate { $date } ; 
			$xaoclose = $xaoclose [ $xaoindex ] ;
			$xaolastclose = $xaoclose [ $xaoindex - 1 ] ;
			$xaodata = ( $xaoclose - $xaolastclose ) / $xaolastclose * 100;
			push $alldata { "XAO" }, $xaodata ;
		}
	}
	
	foreach $code ( @allcodes )
	{
		$alldata { $code } = [];
		$codedata { $code } = {};

		$sql = "$select $wheredateis and code='$code'";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while (@row = $sth->fetchrow_array())
		{
			$date = $row[0];
			$data = $row[1];
			$codedata { $code } { $date } = $data ;
		}		
		$sth->finish();
		
		foreach $date ( sort keys %alldates )
		{
			if ( defined ( $codedata {$code} { $date } ) )   { push $alldata { $code }, $codedata {$code} { $date } ; }
			else {  { push $alldata { $code }, $zero ; }  }
		}
	}

	push @data, \@dates;


	if ( $graphtype eq "lines" )	{ $graph = new GD::Graph::lines(1600, 800); }
	else 				{ $graph = new GD::Graph::bars(1600, 800); }

	foreach $code ( sort keys %alldata )
	{
		if ( defined $alldata { $code } )  { push @data, $alldata { $code } } ;
		if ( defined ( $code ) ) { push @graphlegend, $code } ;
	}

	$graph->set_legend( @graphlegend );

	$graph->set( 
		x_labels_vertical => 1,
		x_label           => 'Trade Date',
		y_label           => '%',
		line_width	  => 3,
		bargroup_spacing  => 10,
		title             => "$code performance compared to market",
		transparent       => 0,
#		fgclr             => [qw(black)],
		y_number_format   => '%0.2f',
#			x_label_skip      => 5,
		long_ticks        => 1,
	) or warn $graph->error;

	$graph->plot(\@data) or die $graph->error;

	my $file = "$graphcode#graphstart#graphend.png";
	open(my $out, '>', $file) or die "Cannot open '$file' for write: $!";
	binmode $out;
	print $out $graph->gd->png;
	close $out;
}

# closing
# sendreport ( "Completed" );
close LOG;

sub sendreport () {
	my $message = $_[0];
	my $smtp = Net::SMTP::SSL->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 1);
	$smtp->auth($smtpuser,$smtppassword);
	$smtp->mail($mailfrom);
	$smtp->to($mailto);
	$smtp->recipient($mailto);
	$smtp->data();
	$smtp->datasend("To: $mailto\n");
	$smtp->datasend("From: $mailfrom\n");
	$smtp->datasend("Subject: $subject\n");
	$smtp->datasend("\n"); # done with header
	$smtp->datasend($message);
	$smtp->dataend();
	
	$smtpcode = $smtp->code();
	$smtpmsg = $smtp->message();
	
	$smtp->quit(); # all done. message sent.
	logentry ( "Mail send result: $smtpcode: $smtpmsg" );
}

sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

