#!/usr/bin/perl

#
# This script updates weekly closing stock prices  
#

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

$test = div0 (1.25,1);

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
my $dbtable = "daily";
my $sql;
my $sth;
my @row;

# Flow control and reporting
my $keepgoing = 1;
my $result;

# Script data
my $Nwk = 10;
my $Nday = 50;
my $stockcount = 0;

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
	# Load stocks

	$sql = "select distinct code from daily order by code";
	$sths = $dbh->prepare($sql);
	$result = $sths->execute();
	while(@srow = $sths->fetchrow_array())
	{

		$stockcount++;
		$code = $srow[0];
		print $code."\n";

		$lastweeklydate = "";
		
		# find what is the latest closing weekly price we know for this stock
		$sql = "select date from weekly where code='$code' order by date desc limit 1";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$lastweeklydate = $row[0];
		}
		$sth->finish();
		
		if ( $lastweeklydate )
		{
			$sql = "select date, close, volume from daily where code='$code' and date > '$lastweeklydate' order by date";
		} else
		{
			$sql = "select date, close, volume from daily where code='$code' order by date";
		}

		$lastday = -1;
		$weekdays = 0 ;
		$weekopen = 0 ;
		$weekhigh = 0 ;
		$weeklow = 0 ;
		$weekclose = 0 ;
		$weekvolume = 0 ;

		$sql = "select date, open, high, low, close, volume from daily where code='$code' order by date";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$date = $row[0];
			$open = $row[1];
			$high = $row[2];
			$low = $row[3];
			$close = $row[4];
			$volume = $row[5];

			( $cyear , $cmonth , $cday ) = split ( "-" , $date );
			$weekday = Day_of_Week ( $cyear , $cmonth , $cday );
			
			if ( $weekday < $lastday )
			{
				# we just started new week
				
				$volume = $weekvolume / $weekdays;
				
				$sql = "insert ignore into weekly SET `code` = '$code', `date` = '$lastdate', `volume` = '$volume', 
					`open` = '$weekopen', `high` = '$weekhigh', `low` = '$weeklow', `close` = '$weekclose'";
				my $sthu = $dbh->prepare($sql);
				$result = $sthu->execute();
				if ( ! $result )
				{
					$thismessage = $sthu->errstr.":".$sql;
					logentry ( $thismessage );
					$message .= $thismessage."\n";
				}
				$sthu->finish();

				$weekvolume = 0 ;
				$weekdays = 0 ;
				$weekopen = 0 ;
				$weekhigh = 0 ;
				$weeklow = 0 ;
				$weekclose = 0 ;
				$weekopen = $open ;
				$weeklow = $low ;
			}
			
			$weekclose = $close ;
			if ( $weekhigh <  $high ) { $weekhigh = $high } ;
			if ( $weeklow >  $low ) { $weeklow = $low } ;
			$weekvolume = $weekvolume + $volume;
			$lastdate = $date;
			$lastday = $weekday;
			$weekdays++;
		}
		
		# This is last known day so lets say it is a end of the week
		
		$volume = $weekvolume / $weekdays;

		$sql = "insert ignore into weekly SET `code` = '$code', `date` = '$lastdate', `volume` = '$volume', 
			`open` = '$weekopen', `high` = '$weekhigh', `low` = '$weeklow', `close` = '$weekclose'";
		my $sthu = $dbh->prepare($sql);
		$result = $sthu->execute();
		if ( ! $result )
		{
			$thismessage = $sthu->errstr.":".$sql;
			logentry ( $thismessage );
			$message .= $thismessage."\n";
		}
		$sthu->finish();
		
		$sth->finish();
	}
	$sths->finish();
}
$dbh->disconnect();

$message .= "Calculated weekly prices for $stockcount stocksk\n";

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

sub div0 () {
	my $num = $_[0];
	my $div = $_[1];
	if ( $div != 0 )
	{
		$div0 = $num/$div;
	}
	else
	{
		$div0 = 0;
	}
	return $div0;
}
