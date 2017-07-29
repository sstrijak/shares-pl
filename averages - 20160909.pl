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
	$sql = "select distinct code from stocks order by code";
	$sths = $dbh->prepare($sql);
	$result = $sths->execute();
	while(@srow = $sths->fetchrow_array())
	{
		$stockcount++;
		$code = $srow[0];
		print $code."\n";
		@pricedaily = ();
		@priceweekly = ();
		@volumedaily = ();
		@volumeweekly = ();
		$lastclose = 0;
		$lastday = 0;
		$lastdate = "";
		$weekday = 0;
		$sql = "select date, close, volume from stocks where code='$code' order by date";
		$sthc = $dbh->prepare($sql);
		$result = $sthc->execute();
		while(@crow = $sthc->fetchrow_array())
		{
			$closedate = $crow[0];
			$close = $crow[1];
			$volume = $crow[2];
			
			if ( $#pricedaily > $Nday) {
				shift @pricedaily;
				shift @volumedaily;
			}
			push @pricedaily, $close;
			push @volumedaily, $volume;

			( $cyear , $cmonth , $cday ) = split ( "-" , $closedate );
			$weekday = Day_of_Week ( $cyear , $cmonth , $cday );
			if ( $weekday < $lastday )
			{
				# we just started new week

				push @priceweekly, $lastclose;
				push @volumeweekly, $lastvolume;

				if ( $#priceweekly > $Nwk )
				{
					shift @priceweekly;
					shift @volumeweekly;
				}
				
				$PNwkLow = min @priceweekly;
				$PNwkHigh = max @priceweekly;
				$PNwkAve = ( sum @priceweekly ) / scalar (@priceweekly);

				$VNwkLow = min @volumeweekly;
				$VNwkHigh = max @volumeweekly;
				$VNwkAve = ( sum @volumeweekly ) / scalar (@volumeweekly);

				$sql = "UPDATE stocks SET 
					`PNwkLow` = '$PNwkLow', `PNwkHigh` = '$PNwkHigh', `PNwkAve` = '$PNwkAve', 
					`VNwkLow` = '$VNwkLow', `VNwkHigh` = '$VNwkHigh', `VNwkAve` = '$VNwkAve',
					`eow` = 1, week = '$lastclose' WHERE `code` = '$code'  and `date` = '$lastdate'";
				my $sthu = $dbh->prepare($sql);
				$result = $sthu->execute();
				if ( ! $result )
				{
					$thismessage = $sthu->errstr.":".$sql;
					logentry ( $thismessage );
					$message .= $thismessage."\n";
				}
				$sthu->finish();
			}

			$PNdayLow = min @pricedaily;
			$PNdayHigh = max @pricedaily;
			$PNdayAve = ( sum @pricedaily ) / scalar (@pricedaily);

			$VNdayLow = min @volumedaily;
			$VNdayHigh = max @volumedaily;
			$VNdayAve = ( sum @volumedaily ) / scalar (@volumedaily);

			$sql = "UPDATE stocks SET 
				`PNdayLow` = '$PNdayLow', `PNdayHigh` = '$PNdayHigh', `PNdayAve` = '$PNdayAve', 
				`VNdayLow` = '$VNdayLow', `VNdayHigh` = '$VNdayHigh', `VNdayAve` = '$VNdayAve'
				WHERE `code` = '$code'  and `date` = '$closedate'";
			my $sthu = $dbh->prepare($sql);
			$result = $sthu->execute();
			if ( ! $result )
			{
				$thismessage = $sthu->errstr.":".$sql;
				logentry ( $thismessage );
				$message .= $thismessage."\n";
			}
			$sthu->finish();
			

			$lastdate = $closedate;
			$lastday = $weekday;
			$lastclose = $close;
			$lastvolume = $volume;
		}
	}
}
$dbh->disconnect();

$message .= "Calculated averages for $stockcount stocksk\n";

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

