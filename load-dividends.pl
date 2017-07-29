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
$htmldir = "../html";

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

	@files = glob("$htmldir/*-Dividends.html");
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
	
	if ( $datafile =~ /$htmldir\/(.*)-Dividends.html/ ) { $code = $1; }

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
	
	$exdate="";
	$paydate="";
	$type="";
	$dividend="";
	$franked="";
	
	foreach $filepart (@fileparts)
	{
		@lines = split ("\\cM", $filepart);
		
		foreach $line (@lines)
		{
			chomp($line);
			$period = "";
			
			if ( $line =~ /DividendsView1_.*_lblDescription.*autocomplete="off">(.*)<\/span>/ )
			{
				$type = $1;
			}
			if ( $line =~ /DividendsView1_.*_lblCentsPerShare.*autocomplete="off">(.*)<\/span>/ )
			{
				$dividend = $1;
				$dividend = $dividend =~ s/,//r;
			}
			if ( $line =~ /DividendsView1_.*_lblFranked.*autocomplete="off">(.*)<\/span>/ )
			{
				$franked = $1;
			}
			if ( $line =~ /DividendsView1_.*_lblExDividendDate.*autocomplete="off">(.*)\/(.*)\/(.*)<\/span>/ )
			{
				$exdate = "$3-$2-$1";
			}
			if ( $line =~ /DividendsView1_.*_lblPayDate.*autocomplete="off">(.*)\/(.*)\/(.*)<\/span>/ )
			{
				$paydate = "$3-$2-$1";
				$sql = "REPLACE INTO `dividends` SET code='$code', exdate = '$exdate', paydate = '$paydate', franked = $franked, dividend = $dividend, type='$type'";
				$sth = $dbh->prepare($sql);
				$result = $sth->execute();
				if ( ! $result )
				{
					$thismessage = $sth->errstr.":".$sql;
					logentry ( $thismessage );
					$message .= $thismessage."\n";
				}
				$sth->finish();

				$type = "";
				$dividend = "";
				$franked = "";
				$exdate = "";
				$paydate = "";
			}
		}
	}
}
$dbh->disconnect();

$message .= "Loaded Dividend files for $filecount files\n";

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

