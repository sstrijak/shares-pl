#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw(Add_Delta_Days);
use Date::Calc qw(Add_Delta_YM);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
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

my @files;
my @fileparts;
my @lines;

my $code;
my $eps;
my $epsg;

my $epsyear;
my $epsmonth;
my $epsday;
my $epsfulldate;
my $epshalfdate;
my $epsdate;

my $filecount = 0;

$epsg = growth ( -708, -4294.20);
print "$currentdate - $preveps -> $currenteps => $epsg \n";


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

	@files = glob("$htmldir/*-Analysis.html");
	if (! @files)
	{
		$thismessage = "No data files in $datadir";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	}
}

foreach $datafile (@files)
{
	$filecount++;
	$keepgoing = 1;	
	
	$eps = -999;
	$epsg = -999;

	if ( $datafile =~ /$htmldir\/(.*)-Analysis.html/ ) { $code = $1; }

	print	 $code."\n";
	
	open DATA, "<", $datafile or do
	{
		$thismessage = "$0: open $datafile: $!";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	};
	
	if ( $keepgoing )
	{
		@fileparts = readline (DATA);
		close DATA;
	}

	if (! @fileparts)
	{
		$thismessage = "No data in $datafile data file";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
	}
	foreach $filepart (@fileparts)
	{
		@lines = split ("\\cM", $filepart);
		
		foreach $line (@lines)
		{
			chomp($line);
			$period = "";
			
			if ( $line =~ /PeriodEnding.*autocomplete=\"off\"\>(.*)\/(.*)\/(.*)\<\/span\>/ )
			{
				$epsyear = $3;
				$epsmonth = $2;
				$epsday = $1;
				$epsfulldate = "$epsyear-$epsmonth-$epsday";
				($epsyear,$epsmonth,$epsday) = Add_Delta_YM ( $epsyear,$epsmonth,$epsday, 0, -6 );
				$epshalfdate = "$epsyear-$epsmonth-$epsday";
			}
			if ( $line =~ /FirstHalf.*\>(.*)\<\/span\>/ )
			{
				$period = "half";
				$epsdate = $epshalfdate;
				$eps = $1;
				$eps =~ s/,//g;
				if ( $eps eq "--" ) { $eps = -999; }
			}

			if ( $line =~ /SecondHalf.*\>(.*)\<\/span\>/ )
			{
				$period = "half";
				$epsdate = $epsfulldate;
				$eps = $1;
				$eps =~ s/,//g;
				if ( $eps eq "--" ) { $eps = -999; }
			}

			if ( $line =~ /FullYear.*\>(.*)\<\/span\>/ )
			{
				$period = "full";
				$epsdate = $epsfulldate;
				$eps = $1;
				$eps =~ s/,//g;
				if ( $eps eq "--" ) { $eps = -999; }
			}
			if ( $period ){
				#check if figures record already exists
				$found = 0;
				$sql = "select code, date, period from fundamentals WHERE code = '$code' and date = '$epsdate' and period = '$period'";
				$sth = $dbh->prepare($sql);
				$result = $sth->execute();
				while(@row = $sth->fetchrow_array())
				{
					$found = 1;
				}
				$sth->finish();

				if ( $found )
				{
					$sql = "UPDATE fundamentals SET eps = '$eps' WHERE code = '$code'  and date = '$epsdate' and period = '$period'";
				}
				else
				{
					$sql = "INSERT INTO fundamentals SET code = '$code', eps = '$eps', date = '$epsdate', period = '$period'";
				}
				$sth = $dbh->prepare($sql);
				$result = $sth->execute();
				if ( ! $result )
				{
					$thismessage = $sth->errstr.":".$sql;
					logentry ( $thismessage );
					$message .= $thismessage."\n";
				}
				$sth->finish();
			}
		}
	}
	
	#calculate half-year growth figures
	$sql = "select date, eps from fundamentals WHERE code = '$code' and period = 'half' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$prevdate = "";
	$preveps = -999;
	while(@row = $sth->fetchrow_array())
	{
		$currentdate = $row[0];
		$currenteps = $row[1];
		if ( $prevdate ) {
			$epsg = growth ( $currenteps, $preveps);
			$sql = "UPDATE fundamentals SET `epsg` = '$epsg' WHERE `code` = '$code'  and `date` = '$currentdate' and `period` = 'half'";
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
		$prevdate = $currentdate;
		$preveps = $currenteps;
	}
	$sth->finish();
	
	#calculate full-year growth figures
	$sql = "select date, eps from fundamentals WHERE code = '$code' and period = 'full' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$prevdate = "";
	$preveps = -999;
	while(@row = $sth->fetchrow_array())
	{
		$currentdate = $row[0];
		$currenteps = $row[1];
		if ( $prevdate ) {
			$epsg = growth ( $currenteps, $preveps);
			$sql = "UPDATE fundamentals SET `epsg` = '$epsg' WHERE `code` = '$code'  and `date` = '$currentdate' and `period` = 'full'";
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
		$prevdate = $currentdate;
		$preveps = $currenteps;
	}
	$sth->finish();
}
$dbh->disconnect();

$message .= "Loaded Analysis files for $filecount files\n";

# closing
#sendreport ( $message );
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

