#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw(Add_Delta_Days);
use Date::Calc qw(Day_of_Week);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
use List::Util qw/min max sum/;
require './growth.pl';

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";
$htmldir = "$mypath/html";

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "stocks";
my $sql;
my $sth;
my @row;

# Flow control and reporting
my $keepgoing = 1;
my $result;

# Script data

$code = "XAO";

########## Read parameters and display help message

open LOG, ">>", $logfile;

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
	$lastclose = 0;
	$lastvolume = 0;
	@distrhist = ();
	@closehist - ();

	$bottomdate = "";
	$rallydate = "";
	$ftdate = "";
	$update = "";

	$bottom = 0;
	$rally = 0;

	$trend = "unclear";

	$sql = "select date, close, volume, VNdayAve from stocks where code='$code' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$closedate = $row[0];
		$close = $row[1];
		$volume = $row[2];
		$avevolume = $row[3];

		$action = "steady";
		$distr = 0;

		# Calculate today action
		if ( $close == $lastclose) { $action = "steady";} 
		else
		{
			if ( $close < $lastclose) { $action = "sell"; }
			else { $action = "buy"; }
			if ( $volume < $avevolume ) { $action = "light ".$action; }
			if ( $volume > $avevolume * 1.2 ) { $action = "heavy ".$action; }
		}

		# Calculate distriution days
		if ( $close <= $lastclose and $volume > $lastvolume ) { $distr = 1; }
		push @distrhist, $distr;
		if ( $#distrhist >= 25 ) { shift @distrhist ; }
		$distnum = sum @distrhist;
		if ( $distnum >= 6 )
		{
			if ( $trend eq "pressure")
			{
				print "correction - $closedate\n";
				print "$bottomdate - $rallydate - $ftdate - $update - $closedate\n";
			}
			$trend = "correction";
		}
		elsif ( $distnum >= 5 )
		{ 
			if ( $trend ne "pressure")
			{
				print "pressure - $closedate\n";
			}
			$trend = "pressure";
		}

		# Calculate uptrend
		if ( $trend eq "correction"  and $close < min @closehist )
		{
			# new low - potential for rebound? - reset bottom day counter
			$bottom = -1;
			$bottomdate = $closedate;
			$rallydate = "";
			$ftdate = "";
			$update = "";
			print "bottom - $closedate\n";
			$rally = 10;
		}

		#Look for attempted rally
		if ( $rally > 10 and $bottom >=0 and $bottom < 3 and $close > $lastclose and $volume > $lastvolume )
		{
			#This looks like an attempted rally
			$rally = -1;
			$rallydate = $closedate;
			$ftdate = "";
			$update = "";
			print "rally - $closedate\n";
		}
		
		if ( $rally >= 0 and $rally < 3 and $close > $lastclose and $volume > $lastvolume )
		{
			$trend = "follow";
			$follow = -1;
			$rally = 10;
			$ftdate = $closedate;
			$update = "";
			print "follow - $closedate\n";
		}	

		if ( $follow >= 0 and $follow < 3 and $close > $lastclose and $volume > $lastvolume )
		{
			$trend = "uptrend";
			$update = $closedate;
			print "uptrend - $closedate\n";
			print "!!! $bottomdate - $rallydate - $ftdate - $update\n";
			$follow = 10;
		}	
		
		push @closehist, $close ;
		if ( $#closehist >= 15 ) { shift @closehist ; }
		$bottom++;
		$rally++;
		$follow++;

		$sql = "UPDATE stocks SET `distr` = $distr, action='$action', trend = '$trend' WHERE `code` = '$code'  and `date` = '$closedate'";
		my $sthu = $dbh->prepare($sql);
		$result = $sthu->execute();
		if ( ! $result )
		{
			$thismessage = $sthu->errstr.":".$sql;
			logentry ( $thismessage );
			$message .= $thismessage."\n";
		}
		$sthu->finish();

		$lastclose = $close;
		$lastvolume = $volume;
	}
}
$dbh->disconnect();

$message .= "Calculated market distribution days\n";

# closing
# sendreport ( $message );
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

