#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw(Add_Delta_Days);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;

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
my $lastdays;
my $lastdate;
my $days;
my $date;
my $stock,$dateymd,$open,$high,$low,$close,$volume;
my $indexvolume;
my $stockcount;

########## Read parameters and display help message
$lastdays = "";
if ( defined ( $ARGV[0] ) ) {
	$lastdays = $ARGV[0];
}

if ( $lastdays eq "" or $lastdays eq "?" or $lastdays eq "-?" or $lastdays eq "-h") {
	print "Usage: perl updatevolumes.pl <N - how many last days>\n";
	print "# This script update index volume figures in the shares database for the last N days \n";
	exit;
}

########## Read parameters and display help message

open LOG, ">>", $logfile;
logentry ("Updating volumes for the last $lastdays days" ); 

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
	#find last date in the table
	$sql = "select max(date) from $dbtable";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array()){
		$lastdate = $row[0];
	}
  	$sth->finish();

	#loop from the last date to 
	$days = $lastdays;
	$date = $lastdate;
	
	while ( $days > 0 )
	{
		$indexvolume = 0;
		$stockcount = 0;
		
		$sql = "SELECT code, volume FROM $dbtable where code like '___' and date='$date' and code NOT IN(SELECT code FROM indexes)";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$stockcount++;
			$indexvolume += $row[1];
		}
		$sth->finish();
		
		#update index XAO volume
		if ( $stockcount )
		{
			$sql = "UPDATE $dbtable SET volume = $indexvolume WHERE code = 'XAO' AND date = '$date'";
			$sth = $dbh->prepare($sql);
			$result = $sth->execute();
			$sth->finish();

			$days--;
		}
		# Calculate new date
		($year,$month,$day) = split ("-",$date);
		($year,$month,$day) = Add_Delta_Days($year,$month,$day,-1);
		$date = "$year-$month-$day";
		print "$date\n";
	}
}
$dbh->disconnect();

$message .= "Volumes for last $lastdays from $lastdate have been updated\n";

# closing
sendreport ( $message );
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

