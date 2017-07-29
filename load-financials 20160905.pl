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

my $yr17;
my $yr16;
my $yr15;
my $yr14;

my $sales17;
my $sales16;
my $sales15;
my $sales14;
my $roe17  ;
my $roe16  ;
my $roe15  ;
my $roe14  ;
my $margin17;
my $margin16;
my $margin15;
my $margin14;

my $sales17g;
my $sales16g;
my $sales15g;
my $sales14g;

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
	
	$sales17= -999;
	$sales16= -999;
	$sales15= -999;
	$sales14= -999;
	$roe17  = -999;
	$roe16  = -999;
	$roe15  = -999;
	$roe14  = -999;
	$margin17= -999;
	$margin16= -999;
	$margin15= -999;
	$margin14= -999;
	$yr17  = "";
	$yr16  = "";
	$yr15  = "";
	$yr14  = "";

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
		
			if ( $line =~ /FinancialsView1_ctl00_ctl00_lblYear(.*)_field.*\>(.*)\/.*\<\/span\>/ )
			{
				$yrlabel = $1;
				$yr = $2;
				if ( $yr eq "2017" ) { $yr17 = $yrlabel; }
				if ( $yr eq "2016" ) { $yr16 = $yrlabel; }
				if ( $yr eq "2015" ) { $yr15 = $yrlabel; }
				if ( $yr eq "2014" ) { $yr14 = $yrlabel; }
			}
			if ( $line =~ /FinancialsView1_ctl00_ctl00_ctl01_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$val = $2;
				$val =~ s/,//g;
				if ( $val ne "--" )
				{
					if ( $yrlabel eq $yr17 ) { $sales17 = $val; }
					if ( $yrlabel eq $yr16 ) { $sales16 = $val; }
					if ( $yrlabel eq $yr15 ) { $sales15 = $val; }
					if ( $yrlabel eq $yr14 ) { $sales14 = $val; }
				}
			}

			if ( $line =~ /FinancialsView1_ctl01_ctl00_ctl02_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$val = $2;
				$val =~ s/,//g;
				if ( $val ne "--" )
				{
					if ( $yrlabel eq $yr17 ) { $margin17 = $val; }
					if ( $yrlabel eq $yr16 ) { $margin16 = $val; }
					if ( $yrlabel eq $yr15 ) { $margin15 = $val; }
					if ( $yrlabel eq $yr14 ) { $margin14 = $val; }
				}
			}

			if ( $line =~ /FinancialsView1_ctl01_ctl00_ctl12_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$val = $2;
				$val =~ s/,//g;
				if ( $val ne "--" )
				{
					if ( $yrlabel eq $yr17 ) { $roe17 = $val; }
					if ( $yrlabel eq $yr16 ) { $roe16 = $val; }
					if ( $yrlabel eq $yr15 ) { $roe15 = $val; }
					if ( $yrlabel eq $yr14 ) { $roe14 = $val; }
				}
			}
		}
	}

	#calculate growth figures

	$sales17g = growth($sales17, $sales16 );
	$sales16g = growth($sales16, $sales15 );
	$sales15g = growth($sales15, $sales14 );

	#Store figure record
	$found = 0;
	$sql = "select code from fundamentals WHERE code = '$code'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$found = 1;
	}
	$sth->finish();

	if ( $found )
	{
		$sql = "UPDATE fundamentals SET
				sales17= '$sales17',
				sales16= '$sales16',
				sales15= '$sales15',
				sales14= '$sales14',
				roe17  = '$roe17',
				roe16  = '$roe16',
				roe15  = '$roe15',
				roe14  = '$roe14',
				margin17= '$margin17',
				margin16= '$margin16',
				margin15= '$margin15',
				margin14= '$margin14'
			WHERE code = '$code'";
	}
	else
	{
		$sql = "INSERT INTO fundamentals SET
				code = '$code',
				sales17= '$sales17',
				sales16= '$sales16',
				sales15= '$sales15',
				sales14= '$sales14',
				roe17  = '$roe17',
				roe16  = '$roe16',
				roe15  = '$roe15',
				roe14  = '$roe14',
				margin17= '$margin17',
				margin16= '$margin16',
				margin15= '$margin15',
				margin14= '$margin14'";
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
	
	#Store growth record
	$found = 0;
	$sql = "select code from growth WHERE code = '$code'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$found = 1;
	}
	$sth->finish();

	if ( $found )
	{
		$sql = "UPDATE growth SET
				sales17g = '$sales17g',
				sales16g = '$sales16g',
				sales15g = '$sales15g'
			WHERE code = '$code'";
	}
	else
	{
		$sql = "INSERT INTO growth SET
				code = '$code',
				sales17g = '$sales17g',
				sales16g = '$sales16g',
				sales15g = '$sales15g'";
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
$dbh->disconnect();

$message .= "Loaded Financials for $filecount files\n";

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

