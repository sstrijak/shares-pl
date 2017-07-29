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
my $RSNwk = 52;
my $RSNday = 250;
my $stockcount = 0;

%stocksondate = {};

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
	# Calculate 200-days RS Index for last 10 days
	%stocksondate = {};

	# get numbers of stock in last 10 days
	$sql = "select date,count(distinct code) from daily where code like '___' group by date order by date desc limit 30";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$stocks = $row[1];
		$stocksondate { $date} = $stocks;
	}
	$sth->finish();

	# calculate 200-days RS Index for each stock on this date
	foreach $date ( keys %stocksondate ) {
	
		@codes = ();
		@RS = ();
	
		print "RSI daily: ".$date."\n";
		$sql = "select code, rsnday from daily where code like '___' and date='$date'";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			push @codes, $row[0];
			push @RS, $row[1];
		}
		$sth->finish();

		for ( $i = 0; $i < scalar(@codes); $i++ )
		{
			$code = $codes[$i];
			$rsnday = $RS[$i];
			$inferiorstocks = 0;
			for ( $j = 0; $j < scalar(@RS); $j++ ) { if ( $RS[$j] < $rsnday ) { $inferiorstocks++; }}
			$rsi = $inferiorstocks / $stocksondate { $date} * 100;

			$stop = $i;

			$sql = "UPDATE daily SET `RSI` = '$rsi' WHERE `code` = '$code'  and `date` = '$date'";
			my $sthu = $dbh->prepare($sql);
			$result = $sthu->execute();
			$sthu->finish();
		}
	}
	
	# Calculate 52-weeks RS Index for last 10 weeks
	%stocksondate = {};
	
	# get numbers of stock in last 10 days
	$sql = "select date,count(distinct code) from weekly where code like '___' group by date order by date desc limit 30";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$stocks = $row[1];
		$stocksondate { $date} = $stocks;
	}
	$sth->finish();

	# calculate 200-days RS Index for each stock on this date
	foreach $date ( keys %stocksondate ) {
	
		@codes = ();
		@RS = ();
	
		print "RSI weekly: ".$date."\n";
		$sql = "select code, RSNwk from weekly where code like '___' and date='$date'";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			push @codes, $row[0];
			push @RS, $row[1];
		}
		$sth->finish();

		$stop = 2;
		
		for ( $i = 0; $i < scalar(@codes); $i++ )
		{
			$code = $codes[$i];
			$rsnday = $RS[$i];
			$inferiorstocks = 0;
			for ( $j = 0; $j < scalar(@RS); $j++ ) { if ( $RS[$j] < $rsnday ) { $inferiorstocks++; }}
			$rsi = $inferiorstocks / $stocksondate { $date} * 100;

			$stop = $i;

			$sql = "UPDATE weekly SET `RSI` = '$rsi' WHERE `code` = '$code'  and `date` = '$date'";
			my $sthu = $dbh->prepare($sql);
			$result = $sthu->execute();
			$sthu->finish();
		}
	}
	
}
$dbh->disconnect();

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