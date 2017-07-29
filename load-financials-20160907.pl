#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw(Add_Delta_Days);
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
my $epsyear;

my %findates;

my %sales;
my %roe  ;
my %margin;
my %sales_g;

my $filecount = 0;

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

	@files = glob("$htmldir/*-Financials.html");
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

	%findates={};	
	%sales={};
	%roe={};
	%margin={};
	%sales_g={};

	if ( $datafile =~ /$htmldir\/(.*)-Financials.html/ ) { $code = $1; }

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
		
			if ( $line =~ /lblYear(.*)_field.*\>(.*)\/(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$finyear = $2;
				$finmonth = $3;
				$findate = "$finyear-$finmonth-30";
				$findates{$yrlabel} = $findate;
			}
			if ( $line =~ /FinancialsView1_ctl00_ctl00_ctl01_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$val = $2;
				$val =~ s/,//g;
				if ( $val ne "--" ) { $sales{$yrlabel} = $val ; }
			}

			if ( $line =~ /FinancialsView1_ctl01_ctl00_ctl02_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$val = $2;
				$val =~ s/,//g;
				if ( $val ne "--" ) { $margin{$yrlabel} = $val ; }
			}

			if ( $line =~ /FinancialsView1_ctl01_ctl00_ctl12_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$val = $2;
				$val =~ s/,//g;
				if ( $val ne "--" ) { $roe{$yrlabel} = $val ; }
			}
		}
	}

	#Store sales figures
	$result = 1;
	foreach $key ( keys %findates )
	{
		$findate = $findates{$key};
		$set = "";
		if ( $sales{$key} ){
			$set =  " sales = '".$sales{$key}."'";
		}
		if ( $roe{$key} )
		{
			if ( $set ) { $set .=  ", "; }  
			$set .=  "roe = '".$roe{$key}."'";
		}
		if ( $margin{$key} )
		{
			if ( $set ) { $set .=  ", "; }  
			$set .=  "margin = '".$margin{$key}."'";
		}
		
		if ( $set ){
			$sql = "UPDATE fundamentals SET $set WHERE code = '$code' and period = 'full' and date = '$findate'";
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
	# Calculate sales growth
	$sql = "select date, sales from fundamentals WHERE code = '$code' and period = 'full' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$prevdate = "";
	$prevsales = -999;
	while(@row = $sth->fetchrow_array())
	{
		$currentdate = $row[0];
		$currentsales = $row[1];
		if ( $prevdate ) {
			$salesg = growth ( $currentsales, $prevsales);
			$sql = "UPDATE fundamentals SET `salesg` = '$salesg' WHERE `code` = '$code'  and `date` = '$currentdate' and `period` = 'full'";
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
		$prevsales = $currentsales;
	}
	$sth->finish();
	
}
$dbh->disconnect();

$message .= "Loaded Financials for $filecount files\n";

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

