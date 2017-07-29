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
my %cashflow;
my %dividends;
my %bookvalue;
my %shares;
my %pe;
my %relpe;
my %de;
my %cash;
my %receivables;
my %inventory;
my %otherassets;
my %debt;
my %payable;
my %otherdebt;
my %totalassets;
my %totalliabilities;

my %salesg;

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

%fields = (
	"sales" => "FinancialsView1_ctl00_ctl00_ctl01",
	"cashflow" => "FinancialsView1_ctl00_ctl00_ctl02",
	"earn" => "FinancialsView1_ctl00_ctl00_ctl03",
	"divs" => "FinancialsView1_ctl00_ctl00_ctl04",
	"capspend" => "FinancialsView1_ctl00_ctl00_ctl06",
	"book" => "FinancialsView1_ctl00_ctl00_ctl07",
	"shares" => "FinancialsView1_ctl00_ctl00_ctl08",
	"pe" => "FinancialsView1_ctl00_ctl00_ctl09",
	"relpe" => "FinancialsView1_ctl00_ctl00_ctl10",
	"totret" => "FinancialsView1_ctl00_ctl00_ctl11",
	"market" => "FinancialsView1_ctl00_ctl00_ctl12",
	"sector" => "FinancialsView1_ctl00_ctl00_ctl13",
	"cover" => "FinancialsView1_ctl00_ctl00_ctl14",
	"gear" => "FinancialsView1_ctl00_ctl00_ctl15",
	"de" => "FinancialsView1_ctl00_ctl00_ctl16",
	"nta" => "FinancialsView1_ctl00_ctl00_ctl17",
	"cap" => "FinancialsView1_ctl00_ctl00_ctl18",
	"dyield" => "FinancialsView1_ctl00_ctl00_ctl19",
	"rev" => "FinancialsView1_ctl01_ctl00_ctl01",
	"margin" => "FinancialsView1_ctl01_ctl00_ctl02",
	"depr" => "FinancialsView1_ctl01_ctl00_ctl03",
	"amort" => "FinancialsView1_ctl01_ctl00_ctl04",
	"npba" => "FinancialsView1_ctl01_ctl00_ctl06",
	"np" => "FinancialsView1_ctl01_ctl00_ctl07",
	"emp" => "FinancialsView1_ctl01_ctl00_ctl08",
	"eq" => "FinancialsView1_ctl01_ctl00_ctl10",
	"roc" => "FinancialsView1_ctl01_ctl00_ctl11",
	"roe" => "FinancialsView1_ctl01_ctl00_ctl12",
	"payout" => "FinancialsView1_ctl01_ctl00_ctl13",
	"roi" => "FinancialsView1_ctl01_ctl00_ctl14",
	"ebitda" => "FinancialsView1_ctl01_ctl00_ctl15",
	"ebit" => "FinancialsView1_ctl01_ctl00_ctl16",
	"cash" => "FinancialsView1_ctl03_ctl00_ctl01",
	"rec" => "FinancialsView1_ctl03_ctl00_ctl02",
	"inv" => "FinancialsView1_ctl03_ctl00_ctl03",
	"oassets" => "FinancialsView1_ctl03_ctl00_ctl04",
	"debt" => "FinancialsView1_ctl03_ctl00_ctl07",
	"pay" => "FinancialsView1_ctl03_ctl00_ctl06",
	"odebt" => "FinancialsView1_ctl03_ctl00_ctl08",
	"tassets" => "FinancialsView1_ctl03_ctl00_ctl05",
	"tdebt" => "FinancialsView1_ctl03_ctl00_ctl09",
);

my $yrlabel;
my $finyear;
my $finmonth;

$filecount = 0;

foreach $datafile (@files)
{
	$filecount++;
	$keepgoing = 1;	

	%stockdata = {};

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
		
			# Financial Year
			if ( $line =~ /FinancialsView1_ctl00_ctl00_lblYear(.*)_field.*\>(.*)\/(.*)\<\/span\>/ )
			{
				$yrlabel = $1;
				$finyear = $2;
				$finmonth = $3;
				$findate = "$finyear-$finmonth-30";
				$findates{$yrlabel} = $findate;
				$stockdata{$findate} = {};
			} elsif ( $line =~ /FinancialsView1_ctl01_ctl00_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
			} elsif ( $line =~ /FinancialsView1_ctl03_ctl00_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
			{
			} else {
				foreach $field ( keys %fields )
				{
					$filter = $fields { $field };
					if ( $line =~ /$filter\_lblYear(.*)_field.*\>(.*)\<\/span\>/ )
					{
						$yrlabel = $1;
						$val = $2;
						$val =~ s/,//g;
						if ( $val ne "--" ) { $stockdata{$yrlabel}{ $field } = $val ; }
					}
				}
			}
		}
	}

	#Store sales figures
	$result = 1;
	foreach $yrlabel ( keys %findates )
	{
		$findate = $findates{$yrlabel};
		$set = "";
		foreach $field ( keys %fields )
		{
			if ( $stockdata{$yrlabel}{$field} ){
				if ( $set ) { $set .= "," ; }
				$set .=  " $field = '".$stockdata{$yrlabel}{$field}."'";
			}
		}
		
		if ( $set ){
		
			$sql = "select date, sales from fundamentals WHERE code = '$code' and period = 'full' and date = '$findate'";
			$sth = $dbh->prepare($sql);
			$result = $sth->execute();
			if ( $sth->fetchrow_array() )
			{
				$sql = "UPDATE fundamentals SET $set WHERE code = '$code' and period = 'full' and date = '$findate'";
			} else
			{
				$sql = "INSERT INTO fundamentals SET $set, code = '$code', period = 'full', date = '$findate'";
			}
			$sth->finish();
			
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

